import 'dart:convert';

import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'package:my_new_app/app/helpers/flutter_toast.dart';
import 'package:my_new_app/app/helpers/shared_preferences.dart';
import 'package:my_new_app/app/repositories/teacherstundentattendance/attendance_repository.dart';
import 'package:my_new_app/app/routes/app_routes.dart';

class DashboardController extends GetxController {
  final AttendanceRepository repository = AttendanceRepository();

  Future<void> handleScannedData(String qrData) async {
    print("QR SCANNED");
    try {
      final Map<String, dynamic> data = jsonDecode(qrData);

      final String classroomId = data["id"]?.toString() ?? "";

      if (classroomId.isEmpty) {
        errorToast("Invalid QR Code");
        return;
      }

      final String roleName =
          await SharedPrefsHelper.getString("roleName") ?? "";

      final String staffId = await SharedPrefsHelper.getString("staffId") ?? "";

      final role = roleName.toLowerCase();

      /// -------------------------------
      /// Teacher Flow
      /// -------------------------------
      if ((role.contains("teacher") || role.contains("lecturer")) &&
          staffId.isNotEmpty) {
      
        // First verify that this classroom/current period belongs to the teacher.
        final contextResponse = await repository.getAttendanceContext(
          classroomId: classroomId,
          teacherId: staffId,
        );
      
        if (contextResponse == null || contextResponse.statusCode != 200) {
          errorToast("Unable to verify classroom");
          return;
        }
      
        final contextBody = contextResponse.data;
      
        if (contextBody["success"] != true) {
          errorToast(
            contextBody["message"] ?? "You are not assigned to this class",
          );
          return;
        }
      
        // Record teacher period attendance.
        // First valid scan = CHECK_IN
        // Later valid scan = CHECK_OUT
        final attendanceResponse = await repository.teacherPeriodQrScan(
          classroomId: classroomId,
        );
      
        if (attendanceResponse == null ||
            (attendanceResponse.statusCode != 200 &&
                attendanceResponse.statusCode != 201)) {
          errorToast("Unable to record teacher attendance");
          return;
        }
      
        final attendanceBody = attendanceResponse.data;
      
        if (attendanceBody["success"] != true) {
          errorToast(
            attendanceBody["message"] ?? "Unable to record teacher attendance",
          );
          return;
        }
      
        final attendanceData = attendanceBody["data"];
      
        if (attendanceData == null) {
          errorToast("Invalid teacher attendance response");
          return;
        }
      
        final String action =
            attendanceData["action"]?.toString().toUpperCase() ?? "";
      
        final bool duplicateScan =
            attendanceData["duplicateScan"] == true;
      
        // ---------------------------------
        // CHECK-IN
        // ---------------------------------
        if (action == "CHECK_IN") {
      
          // Scanner may report the same QR more than once.
          // Backend debounce prevents an accidental checkout.
          if (duplicateScan) {
            return;
          }
      
          successToast("Teacher Check-In Successful");
      
          // Continue the existing student attendance flow.
          Get.toNamed(
            Routes.studentAttendance,
            arguments: {
              "classroomId": classroomId,
            },
          );
      
          return;
        }
      
        // ---------------------------------
        // CHECK-OUT
        // ---------------------------------
        if (action == "CHECK_OUT") {
          final String duration =
              attendanceData["teachingDuration"]?.toString() ?? "";
      
          if (duration.isNotEmpty) {
            successToast(
              "Teacher Check-Out Successful. Duration: $duration",
            );
          } else {
            successToast("Teacher Check-Out Successful");
          }
      
          // IMPORTANT:
          // Do not reopen Student Attendance after checkout.
          return;
        }
      
        errorToast("Unknown teacher attendance action");
        return;
      }

      /// -------------------------------
      /// Other Roles
      /// -------------------------------
      successToast("Successfully Scanned");

      Get.toNamed(
        Routes.studentAttendance,
        arguments: {
          "classroomId": classroomId,
        },
      );
    } catch (e) {
      print("QR ERROR => $e");
      errorToast("Invalid QR Code");
    }
  }

  Future<void> pickQrFromGallery() async {
    try {
      final picker = ImagePicker();

      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) return;

      final inputImage = InputImage.fromFilePath(image.path);

      final barcodeScanner = BarcodeScanner();

      final barcodes = await barcodeScanner.processImage(inputImage);

      await barcodeScanner.close();

      if (barcodes.isEmpty) {
        errorToast("No QR Code found in image");
        return;
      }

      final qrCode = barcodes.first.rawValue;

      if (qrCode == null || qrCode.isEmpty) {
        errorToast("Invalid QR Code");
        return;
      }

      print("QR FROM GALLERY => $qrCode");

      await handleScannedData(qrCode);
    } catch (e) {
      print("QR GALLERY ERROR => $e");

      errorToast("Unable to read QR Code");
    }
  }
}
