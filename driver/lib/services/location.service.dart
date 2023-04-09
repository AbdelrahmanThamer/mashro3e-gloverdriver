import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_location/fl_location.dart';
import 'package:fuodz/constants/app_strings.dart';
import 'package:fuodz/models/delivery_address.dart';
import 'package:fuodz/services/app.service.dart';
import 'package:fuodz/services/auth.service.dart';
// import 'package:geolocator/geolocator.dart';
import 'package:georange/georange.dart';
import 'package:localize_and_translate/localize_and_translate.dart';
import 'package:rxdart/rxdart.dart';

class LocationService {
  //
  static GeoRange georange = GeoRange();
  // static Geolocator location = Geolocator();
  // static LocationSettings locationSettings;
  static Location currentLocationData;
  static DeliveryAddress currentLocation;
  static bool serviceEnabled;
  static FirebaseFirestore firebaseFireStore = FirebaseFirestore.instance;
  static BehaviorSubject<bool> locationDataAvailable =
      BehaviorSubject<bool>.seeded(false);
  static BehaviorSubject<double> driverLocationEarthDistance =
      BehaviorSubject<double>.seeded(0.00);
  static int lastUpdated = 0;
  static StreamSubscription locationUpdateStream;

  //
  static Future<void> prepareLocationListener() async {
    //handle missing permission
    await handlePermissionRequest();
    _startLocationListner();
  }

  static Future<void> handlePermissionRequest({bool background = false}) async {
    if (!await FlLocation.isLocationServicesEnabled) {
      throw "Location service is disabled. Please enable it and try again".tr();
    }

    var locationPermission = await FlLocation.checkLocationPermission();
    if (locationPermission == LocationPermission.deniedForever) {
      // Cannot request runtime permission because location permission is denied forever.
      throw "Location permission denied permanetly. Please check on location permission on app settings"
          .tr();
    } else if (locationPermission == LocationPermission.denied) {
      // Ask the user for location permission.
      locationPermission = await FlLocation.requestLocationPermission();
      if (locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever) {
        throw "Location permission denied. Please check on location permission on app settings"
            .tr();
      }
    }

    // // Location permission must always be allowed (LocationPermission.always)
    // // to collect location data in the background.
    // if (background == true &&
    //     locationPermission == LocationPermission.whileInUse) {
    //   return false;
    // }

    // Location services has been enabled and permission have been granted.
    return true;
  }

  static Stream getNewLocationStream() {
    return FlLocation.getLocationStream(
      interval: AppStrings.timePassLocationUpdate,
      distanceFilter: AppStrings.distanceCoverLocationUpdate ?? 5,
    ).handleError((error) {
      print("Location listen error => $error");
    });
  }

  static void _startLocationListner() async {
    //
    //update location settings
    // locationSettings = LocationSettings(
    //   accuracy: LocationAccuracy.best,
    //   distanceFilter: int.parse(
    //         AppStrings.distanceCoverLocationUpdate.toString(),
    //       ) ??
    //       5,
    //   timeLimit: Duration(
    //     seconds: AppStrings.timePassLocationUpdate,
    //   ),
    // );
    //listen
    locationUpdateStream?.cancel();
    locationUpdateStream = getNewLocationStream().listen((currentPosition) {
      //
      if (currentPosition != null) {
        print("Location changed ==> $currentPosition");
        // Use current location
        if (currentLocation == null) {
          currentLocation = DeliveryAddress();
          locationDataAvailable.add(true);
        }

        currentLocation.latitude = currentPosition.latitude;
        currentLocation.longitude = currentPosition.longitude;
        currentLocationData = currentPosition;
        //
        syncLocationWithFirebase(currentPosition);
      }
    });

    // Geolocator.getPositionStream(locationSettings: locationSettings).listen(
    //     (Position currentPosition) {
    //   if (currentPosition != null) {
    //     print("Location changed ==> $currentPosition");
    //     // Use current location
    //     if (currentLocation == null) {
    //       currentLocation = DeliveryAddress();
    //       locationDataAvailable.add(true);
    //     }

    //     currentLocation.latitude = currentPosition.latitude;
    //     currentLocation.longitude = currentPosition.longitude;
    //     currentLocationData = currentPosition;
    //     //
    //     syncLocationWithFirebase(currentPosition);
    //   }
    //   //
    // }, onError: (error) {
    //   print("Location listen error => $error");
    // });
  }

//
  static syncCurrentLocFirebase() {
    if (currentLocationData != null) {
      syncLocationWithFirebase(currentLocationData);
    }
  }

  //
  static syncLocationWithFirebase(Location currentLocation) async {
    final driverId = (await AuthServices.getCurrentUser()).id.toString();
    //
    if (AppService().driverIsOnline) {
      print("Send to fcm");
      //get distance to earth center
      Point driverLocation = Point(
        latitude: currentLocation.latitude ?? 0.00,
        longitude: currentLocation.longitude ?? 0.00,
      );
      Point earthCenterLocation = Point(
        latitude: 0.00,
        longitude: 0.00,
      );
      //
      var earthDistance =
          georange.distance(earthCenterLocation, driverLocation);

      //
      final driverLocationDocs =
          await firebaseFireStore.collection("drivers").doc(driverId).get();

      //
      final docRef = driverLocationDocs.reference;

      if (driverLocationDocs.data() == null) {
        docRef.set(
          {
            "id": driverId,
            "lat": currentLocation.latitude,
            "long": currentLocation.longitude,
            "rotation": currentLocation.heading,
            "earth_distance": earthDistance,
            "range": AppStrings.driverSearchRadius,
          },
        );
      } else {
        docRef.update(
          {
            "id": driverId,
            "lat": currentLocation.latitude,
            "long": currentLocation.longitude,
            "rotation": currentLocation.heading,
            "earth_distance": earthDistance,
            "range": AppStrings.driverSearchRadius,
          },
        );
      }

      driverLocationEarthDistance.add(earthDistance);
      lastUpdated = DateTime.now().millisecondsSinceEpoch;
    }
  }

  //
  static clearLocationFromFirebase() async {
    final driverId = (await AuthServices.getCurrentUser()).id.toString();
    await firebaseFireStore.collection("drivers").doc(driverId).delete();
  }
}
