//
//  ViewController.swift
//  QRReaderSample
//
//  Created by jollyjoester on 2022/08/20.
//

import UIKit
import AVFoundation
import Vision

final class ViewController: UIViewController {
    
    @IBOutlet private weak var preview: UIView!
    
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: self.session)
        layer.frame = preview.bounds
        layer.videoGravity = .resizeAspectFill
        layer.connection?.videoOrientation = .portrait
        return layer
    }()
    
    @IBOutlet private weak var detectArea: UIView! {
        didSet {
            detectArea.layer.borderWidth = 3.0
            detectArea.layer.borderColor = UIColor.red.cgColor
        }
    }
    
    private var boundingBox = CAShapeLayer()
    
    private var allowDuplicateReading: Bool = false
    private var makeSound: Bool = false
    private var makeHapticFeedback: Bool = false
    private var showBoundingBox: Bool = false
    private var scannedQRs = Set<String>()
    
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    
    private var videoDevice: AVCaptureDevice?
    private var videoDeviceInput: AVCaptureDeviceInput?
    
    private let metadataOutput = AVCaptureMetadataOutput()
    private let metadataObjectQueue = DispatchQueue(label: "metadataObjectQueue")
    
// VisionでQR検知したい場合はコメントアウトしてね
//    private let videoDataQueue = DispatchQueue(label: "videoDataQueue")
//    private lazy var videoDataOutput: AVCaptureVideoDataOutput = {
//        let output = AVCaptureVideoDataOutput()
//        output.setSampleBufferDelegate(self, queue: self.videoDataQueue)
//        return output
//    }()
    
// VisionでQR検知したい場合はコメントアウトしてね
//    let requestHandler = VNSequenceRequestHandler()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    // 😭
                }
            }
        default:
            print("The user has previously denied access.")
        }
        
        DispatchQueue.main.async {
            self.setupBoundingBox()
        }
        
        sessionQueue.async {
            self.configureSession()
        }
        
        preview.layer.addSublayer(previewLayer)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 読み取り範囲の制限
        sessionQueue.async {
            DispatchQueue.main.async {
                print(self.detectArea.frame)
                let metadataOutputRectOfInterest = self.previewLayer.metadataOutputRectConverted(fromLayerRect: self.detectArea.frame)
                print(metadataOutputRectOfInterest)
                self.sessionQueue.async {
                    self.metadataOutput.rectOfInterest = metadataOutputRectOfInterest
                }
            }
            
            self.session.startRunning()
        }
    }
    
    // MARK: configureSession
    private func configureSession() {
        session.beginConfiguration()
        
        let defaultVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                         for: .video,
                                                         position: .back)
        
        guard let videoDevice = defaultVideoDevice else {
            session.commitConfiguration()
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            }
        } catch {
            session.commitConfiguration()
            return
        }
        
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: metadataObjectQueue)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            session.commitConfiguration()
        }
        
// VisionでQR検知したい場合はコメントアウトしてね
//        if session.canAddOutput(videoDataOutput) {
//            session.addOutput(videoDataOutput)
//
//            videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataQueue)
//        }
        
        session.commitConfiguration()
    }
    
    private func setupBoundingBox() {
        boundingBox.frame = preview.layer.bounds
        boundingBox.strokeColor = UIColor.green.cgColor
        boundingBox.lineWidth = 4.0
        boundingBox.fillColor = UIColor.clear.cgColor
        
        preview.layer.addSublayer(boundingBox)
    }
    
    // MARK: Zoom
    private func setZoomFactor(_ zoomFactor: CGFloat) {
        guard let videoDeviceInput = self.videoDeviceInput else { return }
        do {
            try videoDeviceInput.device.lockForConfiguration()
            videoDeviceInput.device.videoZoomFactor = zoomFactor
            videoDeviceInput.device.unlockForConfiguration()
        } catch {
            print("Could not lock for configuration: \(error)")
        }
    }
    
    // MARK: Torch
    private func switchTorch(_ mode: AVCaptureDevice.TorchMode) {
        guard let videoDeviceInput = self.videoDeviceInput,
              videoDeviceInput.device.hasTorch == true,
              videoDeviceInput.device.isTorchAvailable == true
        else { return }
        do {
            try videoDeviceInput.device.lockForConfiguration()
            videoDeviceInput.device.torchMode = mode
            videoDeviceInput.device.unlockForConfiguration()
        } catch {
            print("Could not lock for configuration: \(error)")
        }
    }
    
    // MARK: Sounds
    private func playSuccessSound() {
        if makeSound == true {
            let soundIdRing: SystemSoundID = 1057
            AudioServicesPlaySystemSound(soundIdRing)
        }
    }
    
    private func playErrorSound() {
        if makeSound == true {
            let soundIdError: SystemSoundID = 1073
            AudioServicesPlayAlertSound(soundIdError)
        }
    }
    
    // MARK: Haptic feedback
    private func HapticSuccessNotification() {
        if makeHapticFeedback == true {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        }
    }
    
    private func HapticErrorNotification() {
        if makeHapticFeedback == true {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.error)
        }
    }
    
    // Draw bounding box
    private func updateBoundingBox(_ points: [CGPoint]) {
        guard let firstPoint = points.first else {
            return
        }
        
        let path = UIBezierPath()
        path.move(to: firstPoint)
        
        var newPoints = points
        newPoints.removeFirst()
        newPoints.append(firstPoint)
        
        newPoints.forEach { path.addLine(to: $0) }
        
        boundingBox.path = path.cgPath
        boundingBox.isHidden = false
    }
    
    private var resetTimer: Timer?
    fileprivate func hideBoundingBox(after: Double) {
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval() + after,
                                          repeats: false) { [weak self] (timer) in
            self?.boundingBox.isHidden = true }
    }
    
    private func resetViews() {
        boundingBox.isHidden = true
    }
    
    @IBAction func switchTorch(_ sender: UISwitch) {
        if sender.isOn {
            switchTorch(.on)
        } else {
            switchTorch(.off)
        }
    }
    
    @IBAction func makeSound(_ sender: UISwitch) {
        if sender.isOn {
            makeSound = true
        } else {
            makeSound = false
        }
    }
    
    @IBAction func makeHaptic(_ sender: UISwitch) {
        if sender.isOn {
            makeHapticFeedback = true
        } else {
            makeHapticFeedback = false
        }
    }
    
    @IBAction func allowDuplicateReading(_ sender: UISwitch) {
        scannedQRs = []
        if sender.isOn {
            allowDuplicateReading = true
        } else {
            allowDuplicateReading = false
        }
    }
    
    @IBAction func showBoundingBox(_ sender: UISwitch) {
        if sender.isOn {
            showBoundingBox = true
        } else {
            showBoundingBox = false
        }
    }
    
    @IBAction func changeZoom(_ sender: UISlider) {
        setZoomFactor(CGFloat(sender.value))
    }
}

// MARK: AVCaptureMetadataOutputObjectsDelegate
extension ViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        for metadataObject in metadataObjects {
            guard let machineReadableCode = metadataObject as? AVMetadataMachineReadableCodeObject,
                  machineReadableCode.type == .qr,
                  let stringValue = machineReadableCode.stringValue
            else {
                return
            }
            
            if showBoundingBox {
                guard let transformedObject = previewLayer.transformedMetadataObject(for: machineReadableCode) as? AVMetadataMachineReadableCodeObject
                else { return }
                
                DispatchQueue.main.async {
                    self.updateBoundingBox(transformedObject.corners)
                    self.hideBoundingBox(after: 0.1)
                }
            }
            
            if allowDuplicateReading {
                if !self.scannedQRs.contains(stringValue) {
                    self.scannedQRs.insert(stringValue)
                    
                    // 読み取り成功🎉
                    self.playSuccessSound()
                    self.HapticSuccessNotification()
                    print("The content of QR code: \(stringValue)")
                }
            } else {
                // 読み取り成功🎉
                self.playSuccessSound()
                self.HapticSuccessNotification()
                print("The content of QR code: \(stringValue)")
            }
        }
    }
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate
// VisionでQR検知したい場合はコメントアウトしてね
//extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//            return;
//        }
//
//        let detectRequest = VNDetectBarcodesRequest { [weak self](request, error) in
//            guard let self = self else { return }
//            guard let results = request.results as? [VNBarcodeObservation] else {
//                return
//            }
//
//            for observation in results {
//                if let payloadString = observation.payloadStringValue {
//                    if !self.scannedQRs.contains(payloadString) {
//                        print("The content of QR code: \(payloadString)")
//                        self.playSuccessSound()
//                        self.scannedQRs.insert(payloadString)
//                    }
//                }
//            }
//        }
//        detectRequest.symbologies = [VNBarcodeSymbology.qr]
//
//        do {
//            try requestHandler.perform([detectRequest], on: pixelBuffer)
//        } catch {
//            print(error.localizedDescription)
//        }
//    }
//}
