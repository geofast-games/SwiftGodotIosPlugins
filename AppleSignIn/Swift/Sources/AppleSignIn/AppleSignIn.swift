//
//  AppleSignIn.swift
//  SwiftGodotIosPlugins
//
//  Apple Sign-In authentication plugin for Godot using SwiftGodot
//

import AuthenticationServices
import SwiftGodot

#if canImport(UIKit)
    import UIKit
#endif

#initSwiftExtension(
    cdecl: "applesignin",
    types: [
        AppleSignIn.self,
    ]
)

enum AppleSignInError: Int, Error {
    case unknownError = 1
    case canceled = 2
    case invalidResponse = 3
    case notHandled = 4
    case failed = 5
    case notAvailable = 6
    case notInteractive = 7
}

@Godot
class AppleSignIn: Object {

    // MARK: - Signals

    /// Emitted when Apple Sign-In completes successfully
    /// Parameters: identityToken (String), authorizationCode (String), userIdentifier (String), email (String), fullName (String)
    @Signal var signInSuccess: SignalWithArguments<String, String, String, String, String>

    /// Emitted when Apple Sign-In fails
    /// Parameters: errorCode (Int), errorMessage (String)
    @Signal var signInFailed: SignalWithArguments<Int, String>

    /// Emitted when Apple Sign-In is cancelled by user
    @Signal var signInCancelled: SimpleSignal

    /// Emitted when credential state check completes
    /// Parameters: userIdentifier (String), isAuthorized (Bool)
    @Signal var credentialStateChecked: SignalWithArguments<String, Bool>

    // MARK: - Properties

    static var shared: AppleSignIn?

    // Store delegate to prevent deallocation
    private var currentDelegate: AppleSignInDelegate?

    #if canImport(UIKit)
    private var presentationAnchor: ASPresentationAnchor? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return nil
        }
        return window
    }
    #endif

    // MARK: - Initialization

    required override init() {
        super.init()
        AppleSignIn.shared = self
        GD.print("[AppleSignIn] Plugin initialized via init()")
    }

    required init(nativeHandle: UnsafeRawPointer) {
        super.init(nativeHandle: nativeHandle)
        AppleSignIn.shared = self
        GD.print("[AppleSignIn] Plugin initialized via nativeHandle")
    }

    // MARK: - Public Methods

    /// Check if Apple Sign-In is available on this device
    /// Returns true if Apple Sign-In is available
    @Callable
    func isAvailable() -> Bool {
        GD.print("[AppleSignIn] isAvailable() called")
        #if canImport(UIKit)
        if #available(iOS 13.0, *) {
            GD.print("[AppleSignIn] isAvailable() returning true (iOS 13+)")
            return true
        }
        #endif
        GD.print("[AppleSignIn] isAvailable() returning false")
        return false
    }

    /// Start Apple Sign-In flow
    /// Requests full name and email scopes
    ///
    /// - Signals:
    ///     - sign_in_success: identityToken, authorizationCode, userIdentifier, email, fullName
    ///     - sign_in_failed: errorCode, errorMessage
    ///     - sign_in_cancelled: emitted when user cancels
    @Callable
    func signIn() {
        GD.print("[AppleSignIn] signIn() called")
        #if canImport(UIKit)
        signInInternal(requestEmail: true, requestFullName: true)
        #else
        GD.print("[AppleSignIn] UIKit not available, emitting failure")
        signInFailed.emit(AppleSignInError.notAvailable.rawValue, "Apple Sign-In is not available on this platform")
        #endif
    }

    /// Start Apple Sign-In flow with custom scopes
    ///
    /// - Parameters:
    ///     - requestEmail: Whether to request user's email
    ///     - requestFullName: Whether to request user's full name
    ///
    /// - Signals:
    ///     - sign_in_success: identityToken, authorizationCode, userIdentifier, email, fullName
    ///     - sign_in_failed: errorCode, errorMessage
    ///     - sign_in_cancelled: emitted when user cancels
    @Callable
    func signInWithScopes(requestEmail: Bool, requestFullName: Bool) {
        GD.print("[AppleSignIn] signInWithScopes() called - email: \(requestEmail), fullName: \(requestFullName)")
        #if canImport(UIKit)
        signInInternal(requestEmail: requestEmail, requestFullName: requestFullName)
        #else
        GD.print("[AppleSignIn] UIKit not available, emitting failure")
        signInFailed.emit(AppleSignInError.notAvailable.rawValue, "Apple Sign-In is not available on this platform")
        #endif
    }

    /// Check the credential state for a user identifier
    /// Use this to verify if the user's Apple ID credentials are still valid
    ///
    /// - Parameters:
    ///     - userIdentifier: The user identifier from a previous sign-in
    ///
    /// - Signals:
    ///     - credential_state_checked: userIdentifier, isAuthorized
    @Callable
    func checkCredentialState(userIdentifier: String) {
        GD.print("[AppleSignIn] checkCredentialState() called for user: \(userIdentifier)")
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: userIdentifier) { [weak self] credentialState, error in
            DispatchQueue.main.async {
                guard let self = self else {
                    GD.print("[AppleSignIn] checkCredentialState: self is nil")
                    return
                }

                if let error = error {
                    GD.print("[AppleSignIn] checkCredentialState error: \(error.localizedDescription)")
                    GD.pushWarning("Credential state check error: \(error.localizedDescription)")
                    self.credentialStateChecked.emit(userIdentifier, false)
                    return
                }

                GD.print("[AppleSignIn] checkCredentialState result: \(credentialState.rawValue)")
                switch credentialState {
                case .authorized:
                    self.credentialStateChecked.emit(userIdentifier, true)
                case .revoked, .notFound, .transferred:
                    self.credentialStateChecked.emit(userIdentifier, false)
                @unknown default:
                    self.credentialStateChecked.emit(userIdentifier, false)
                }
            }
        }
    }

    // MARK: - Internal Methods

    #if canImport(UIKit)
    private func signInInternal(requestEmail: Bool, requestFullName: Bool) {
        GD.print("[AppleSignIn] signInInternal() starting...")

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        GD.print("[AppleSignIn] Created Apple ID request")

        var scopes: [ASAuthorization.Scope] = []
        if requestEmail {
            scopes.append(.email)
        }
        if requestFullName {
            scopes.append(.fullName)
        }
        request.requestedScopes = scopes
        GD.print("[AppleSignIn] Requested scopes: \(scopes)")

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        GD.print("[AppleSignIn] Created ASAuthorizationController")

        let delegate = AppleSignInDelegate(plugin: self)

        // Store delegate as instance property to prevent deallocation
        self.currentDelegate = delegate
        GD.print("[AppleSignIn] Created and stored delegate")

        // Also store delegate on controller
        objc_setAssociatedObject(
            authorizationController,
            "delegate",
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        GD.print("[AppleSignIn] Associated delegate with controller")

        authorizationController.delegate = delegate
        authorizationController.presentationContextProvider = delegate
        GD.print("[AppleSignIn] Set delegate and presentationContextProvider")

        GD.print("[AppleSignIn] Calling performRequests()...")
        authorizationController.performRequests()
        GD.print("[AppleSignIn] performRequests() called - waiting for callback")
    }
    #endif

    // MARK: - Callback Methods (called by delegate)

    func handleAuthorizationSuccess(credential: ASAuthorizationAppleIDCredential) {
        GD.print("[AppleSignIn] handleAuthorizationSuccess() called")

        let userIdentifier = credential.user
        GD.print("[AppleSignIn] User identifier: \(userIdentifier)")

        // Get identity token (JWT)
        var identityToken = ""
        if let tokenData = credential.identityToken,
           let tokenString = String(data: tokenData, encoding: .utf8) {
            identityToken = tokenString
            GD.print("[AppleSignIn] Identity token length: \(identityToken.count)")
        } else {
            GD.print("[AppleSignIn] WARNING: No identity token received")
        }

        // Get authorization code
        var authorizationCode = ""
        if let codeData = credential.authorizationCode,
           let codeString = String(data: codeData, encoding: .utf8) {
            authorizationCode = codeString
            GD.print("[AppleSignIn] Authorization code length: \(authorizationCode.count)")
        } else {
            GD.print("[AppleSignIn] WARNING: No authorization code received")
        }

        // Get email (may be nil on subsequent sign-ins)
        let email = credential.email ?? ""
        GD.print("[AppleSignIn] Email: \(email.isEmpty ? "(empty)" : email)")

        // Get full name
        var fullName = ""
        if let nameComponents = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            fullName = formatter.string(from: nameComponents)
        }
        GD.print("[AppleSignIn] Full name: \(fullName.isEmpty ? "(empty)" : fullName)")

        GD.print("[AppleSignIn] Emitting signInSuccess signal...")
        signInSuccess.emit(identityToken, authorizationCode, userIdentifier, email, fullName)
        GD.print("[AppleSignIn] signInSuccess signal emitted")

        // Clear delegate reference
        self.currentDelegate = nil
    }

    func handleAuthorizationError(_ error: Error) {
        GD.print("[AppleSignIn] handleAuthorizationError() called")
        GD.print("[AppleSignIn] Error: \(error.localizedDescription)")
        GD.print("[AppleSignIn] Error domain: \((error as NSError).domain)")
        GD.print("[AppleSignIn] Error code: \((error as NSError).code)")

        if let authError = error as? ASAuthorizationError {
            GD.print("[AppleSignIn] ASAuthorizationError code: \(authError.code.rawValue)")
            switch authError.code {
            case .canceled:
                GD.print("[AppleSignIn] User cancelled - emitting signInCancelled")
                signInCancelled.emit()
                self.currentDelegate = nil
                return
            case .invalidResponse:
                GD.print("[AppleSignIn] Invalid response - emitting signInFailed")
                signInFailed.emit(AppleSignInError.invalidResponse.rawValue, "Invalid response from Apple")
            case .notHandled:
                GD.print("[AppleSignIn] Not handled - emitting signInFailed")
                signInFailed.emit(AppleSignInError.notHandled.rawValue, "Request not handled")
            case .failed:
                GD.print("[AppleSignIn] Failed - emitting signInFailed")
                signInFailed.emit(AppleSignInError.failed.rawValue, "Authorization failed: \(authError.localizedDescription)")
            case .notInteractive:
                GD.print("[AppleSignIn] Not interactive - emitting signInFailed")
                signInFailed.emit(AppleSignInError.notInteractive.rawValue, "Not interactive")
            case .unknown:
                GD.print("[AppleSignIn] Unknown error - emitting signInFailed")
                signInFailed.emit(AppleSignInError.unknownError.rawValue, "Unknown error: \(authError.localizedDescription)")
            @unknown default:
                GD.print("[AppleSignIn] Unknown default - emitting signInFailed")
                signInFailed.emit(AppleSignInError.unknownError.rawValue, "Unknown error: \(authError.localizedDescription)")
            }
        } else {
            GD.print("[AppleSignIn] Non-ASAuthorizationError - emitting signInFailed")
            signInFailed.emit(AppleSignInError.unknownError.rawValue, "Error: \(error.localizedDescription)")
        }

        // Clear delegate reference
        self.currentDelegate = nil
    }
}

// MARK: - Apple Sign-In Delegate

#if canImport(UIKit)
class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    weak var plugin: AppleSignIn?

    init(plugin: AppleSignIn) {
        self.plugin = plugin
        super.init()
        GD.print("[AppleSignInDelegate] Delegate initialized")
    }

    deinit {
        GD.print("[AppleSignInDelegate] Delegate deallocated")
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        GD.print("[AppleSignInDelegate] didCompleteWithAuthorization called")
        GD.print("[AppleSignInDelegate] Credential type: \(type(of: authorization.credential))")

        DispatchQueue.main.async { [weak self] in
            GD.print("[AppleSignInDelegate] Inside main queue async block")

            guard let self = self else {
                GD.print("[AppleSignInDelegate] ERROR: self is nil in async block")
                return
            }

            guard let plugin = self.plugin else {
                GD.print("[AppleSignInDelegate] ERROR: plugin is nil")
                return
            }

            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                GD.print("[AppleSignInDelegate] Got ASAuthorizationAppleIDCredential, calling handleAuthorizationSuccess")
                plugin.handleAuthorizationSuccess(credential: appleIDCredential)
            } else {
                GD.print("[AppleSignInDelegate] ERROR: Invalid credential type")
                plugin.handleAuthorizationError(
                    NSError(domain: "AppleSignIn", code: AppleSignInError.invalidResponse.rawValue, userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"])
                )
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        GD.print("[AppleSignInDelegate] didCompleteWithError called")
        GD.print("[AppleSignInDelegate] Error: \(error.localizedDescription)")

        DispatchQueue.main.async { [weak self] in
            GD.print("[AppleSignInDelegate] Inside error main queue async block")

            guard let self = self else {
                GD.print("[AppleSignInDelegate] ERROR: self is nil in error async block")
                return
            }

            guard let plugin = self.plugin else {
                GD.print("[AppleSignInDelegate] ERROR: plugin is nil in error handler")
                return
            }

            GD.print("[AppleSignInDelegate] Calling handleAuthorizationError")
            plugin.handleAuthorizationError(error)
        }
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        GD.print("[AppleSignInDelegate] presentationAnchor() called")

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            GD.print("[AppleSignInDelegate] WARNING: Could not get window, creating fallback")
            return UIWindow()
        }

        GD.print("[AppleSignInDelegate] Returning window as presentation anchor")
        return window
    }
}
#endif
