import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import '../network/remote_data_sources.dart';

final authControllerProvider = ChangeNotifierProvider<AppAuthController>(
  (ref) =>
      throw StateError('AppAuthController must be provided at the app root'),
);

class AppAuthController extends ChangeNotifier {
  AppAuthController(
      {required AuthRemoteDataSource auth,
      required DeviceIdentity deviceIdentity,
      Future<void> Function()? onAuthenticated,
      Future<void> Function()? onLoggedOut})
      : _auth = auth,
        _deviceIdentity = deviceIdentity,
        _onAuthenticated = onAuthenticated,
        _onLoggedOut = onLoggedOut;

  final AuthRemoteDataSource _auth;
  final DeviceIdentity _deviceIdentity;
  final Future<void> Function()? _onAuthenticated;
  final Future<void> Function()? _onLoggedOut;

  String invitationCode = '';
  String registrationEmail = '';
  String registrationPassword = '';
  String? developmentVerificationCode;
  bool isBusy = false;
  String? errorMessage;

  void setInvitation(String value) => invitationCode = value.trim();

  void setRegistrationCredentials(String email, String password) {
    registrationEmail = email.trim();
    registrationPassword = password;
  }

  Future<bool> register(
          {required String username, required String displayName}) =>
      _run(() async {
        developmentVerificationCode = await _auth.register(
          invitationCode: invitationCode,
          email: registrationEmail,
          username: username.trim(),
          displayName: displayName.trim(),
          password: registrationPassword,
        );
      });

  Future<bool> verify(String code) =>
      _run(() => _auth.verifyEmail(registrationEmail, code.trim()));

  Future<bool> login(String email, String password) => _run(() async {
        await _auth.login(
          email: email.trim(),
          password: password,
          deviceUuid: await _deviceIdentity.getOrCreate(),
        );
        await _onAuthenticated?.call();
      });

  Future<void> logout() async {
    await _auth.logout();
    await _onLoggedOut?.call();
  }

  Future<bool> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      return false;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
