import UIKit
import AVFoundation
import OSLog

class CaptureVideoViewController: UIViewController {
    private let previewView: PreviewView = PreviewView()

    // MARK: - Session Management
    private var setupResult: SessionSetupResult = .success
    private let session: AVCaptureSession = AVCaptureSession()
    private var isSessionRunning: Bool = false
    private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput!
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue: DispatchQueue = DispatchQueue(label: "com.CaptureVideo.sessionQueue")
    private let videoDataObjectsQueue: DispatchQueue = DispatchQueue(label: "com.CaptureVideo.videoDataObjectsQueue")

    // Call this on the session queue.
    private func configureSession() {
        guard self.setupResult == .success else {
            os_log("Could not start configuring session. Reason - setup result is: %@", type: .info, "\(setupResult)")
            return
        }

        // Begin configuring the AVCapture session.
        session.beginConfiguration()

        // Ensure that the configuration is committed, whether the configuration succeeds or an error occurs.
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        // Attempt to get the default video device, prioritizing the back wide-angle camera.
        let defaultVideoDevice: AVCaptureDevice?

        if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            defaultVideoDevice = backCameraDevice
        } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            // If the back wide-angle camera is unavailable, use the front wide-angle camera.
            defaultVideoDevice = frontCameraDevice
        } else {
            defaultVideoDevice = nil
        }

        // Ensure a valid video device is obtained.
        guard let videoDevice = defaultVideoDevice else {
            setupResult = .configurationFailed
            os_log("Could not get video device", type: .error)
            return
        }

        do {
            // Create a AVCaptureDeviceInput instance with the obtained video device.
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                
                // Desired frame rate - 60FPS
                let targetFrameRate = 60
                // Disable smooth auto-focus if supported by the video device.
                if videoDevice.isSmoothAutoFocusSupported {
                    try videoDevice.lockForConfiguration()
                    videoDevice.isSmoothAutoFocusEnabled = false
                    videoDevice.unlockForConfiguration()
                }

                // Set the desired frame rate and configure the active format.
                try videoDevice.lockForConfiguration()

                // Select the initial format as a fallback.
                var formatToSet: AVCaptureDevice.Format = videoDeviceInput.device.formats[0]
                
                // Iterate through available formats to find the one matching the desired frame rate and resolution.
                for format in videoDeviceInput.device.formats.reversed() {
                    let ranges = format.videoSupportedFrameRateRanges
                    let frameRates = ranges[0]

                    // Check if the format matches the desirable frame rate and resolution (1280x720).
                    if frameRates.maxFrameRate == Double(targetFrameRate),
                       format.formatDescription.dimensions.width == 1280,
                       format.formatDescription.dimensions.height == 720
                    {
                        // Set the format to the matching one.
                        formatToSet = format

                        // Log the chosen active format.
                        os_log("Video device active format was chosen: %{public}@", type: .info, format.description)

                        // Exit the loop as the desired format is found.
                        break
                    }
                }
                // Apply the selected format to the video device.
                videoDevice.activeFormat = formatToSet

                // Set the desired frame rate(60FPS).
                let timescale = CMTimeScale(targetFrameRate)
                // Ensure activeFormat supports 60 frames per second before setting frame duration.
                // This place would crash if you didn't set activeFormat to one that can handle 60 frames per second.
                if videoDevice.activeFormat.videoSupportedFrameRateRanges[0].maxFrameRate >= Double(targetFrameRate) {
                    videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: timescale)
                    videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: timescale)
                } else {
                    // Log a warning if the selected format doesn't support 60FPS.
                    os_log("Selected active format may not support the desired frame rate of %{public}d FPS.", type: .error, targetFrameRate)
                }

                // Unlock the video device configuration.
                videoDevice.unlockForConfiguration()

                // Set the configured video device input for later use.
                self.videoDeviceInput = videoDeviceInput

                DispatchQueue.main.async {
                    /*
                     AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
                     can only be manipulated on the main thread.
                     Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.

                     Use the window orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }

                    self.previewView.videoPreviewLayer.connection!.videoOrientation = initialVideoOrientation
                }
            } else {
                setupResult = .configurationFailed
                os_log("Could not add video device input to the session", type: .info)
                return
            }
        } catch {
            setupResult = .configurationFailed
            os_log("Could not create video device input: %@", type: .error, error.localizedDescription)
            return
        }

        // Add video data output.
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            // Set this view controller as the delegate for video data objects.
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataObjectsQueue)
            videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA] // Set the pixel format for video frame capture.
        } else {
            setupResult = .configurationFailed
            os_log("Could not add video data output to the session", type: .info)
            return
        }
    }


    // MARK: - View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Set up PreviewView

        // Add your custom view as a subview
        view.addSubview(previewView)

        // Configure Auto Layout constraints
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Initialize and configure the video preview view.
        previewView.session = session

        // Check video authorization status.
        // Video access is mandatory.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break

        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Session queue is suspended to delay session
             setup until the access request has completed.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })

        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }

        // Setup the capture session.
        sessionQueue.async {
            self.configureSession()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning

            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCamBarcode doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCamBarcode", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { _ in
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
                    }))

                    self.present(alertController, animated: true, completion: nil)
                }

            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Unable to capture media"
                    let message = NSLocalizedString(alertMsg, comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCamBarcode", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))

                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }

        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue),
                  deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }

            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }

    private var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

}

extension CaptureVideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // do what you need to do with captured frames
    }
}

// MARK: - Notifications and Observers
extension CaptureVideoViewController {
    private func addObservers() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)

        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        notificationCenter.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        notificationCenter.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
    }

    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            os_log("Could not reach error when sessionRuntimeError occurred", type: .error)
            return
        }

        os_log("Capture session runtime error: %@", type: .error, error.localizedDescription)

        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios we want to enable the user to resume the session running.
         For example, if music playback is initiated via control center while
         using AVCamBarcode, then the user can let AVCamBarcode resume
         the session running, which will stop music playback. Note that stopping
         music playback in control center will not automatically resume the session
         running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
           let reasonIntegerValue = userInfoValue.integerValue,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            os_log("Capture session was interrupted with reason %@", type: .error, "\(reason)")
        }
    }

    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        os_log("Capture session interruption ended", type: .info)
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}
