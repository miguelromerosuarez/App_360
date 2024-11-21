import UIKit
import AVFoundation
import CoreMotion

class ViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureMovieFileOutput?
    var motionManager: CMMotionManager?
    var timer: Timer?
    var outputFilePath: URL?
    var library = UIImagePickerController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupMotionSensor()
    }

    func setupCamera() {
        // Configurar la sesión de captura de video
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        videoOutput = AVCaptureMovieFileOutput()
        if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        captureSession.startRunning()
    }

    func setupMotionSensor() {
        // Configurar el sensor de movimiento
        motionManager = CMMotionManager()
        motionManager?.startAccelerometerUpdates(to: OperationQueue.current!) { [weak self] (data, error) in
            guard let self = self, let accelerometerData = data else { return }
            let threshold: Double = 1.5 // Definir umbral de detección de movimiento
            if abs(accelerometerData.acceleration.x) > threshold ||
                abs(accelerometerData.acceleration.y) > threshold ||
                abs(accelerometerData.acceleration.z) > threshold {
                self.startRecording()
            }
        }
    }

    func startRecording() {
        guard let videoOutput = videoOutput, let captureSession = captureSession else { return }
        if !videoOutput.isRecording {
            let tempDir = NSTemporaryDirectory()
            outputFilePath = URL(fileURLWithPath: tempDir).appendingPathComponent("temp.mov")
            captureSession.startRunning()
            videoOutput.startRecording(to: outputFilePath!, recordingDelegate: self)
            // Iniciar el temporizador para detener la grabación después de 10 segundos
            timer = Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(stopRecording), userInfo: nil, repeats: false)
        }
    }

    @objc func stopRecording() {
        videoOutput?.stopRecording()
    }

    func editVideoInSlowMotion(_ videoURL: URL) {
        // Aplicar el efecto de cámara lenta al video
        let asset = AVAsset(url: videoURL)
        let composition = AVMutableComposition()
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        do {
            try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: track, at: .zero)
            compositionTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: asset.duration), toDuration: CMTimeMultiplyByFloat64(asset.duration, multiplier: 2.0)) // Doble duración para cámara lenta
        } catch {
            print("Error al agregar el efecto de cámara lenta: \(error)")
            return
        }
        exportEditedVideo(composition)
    }

    func exportEditedVideo(_ composition: AVMutableComposition) {
        guard let outputFilePath = outputFilePath else { return }
        let exportPath = outputFilePath.deletingLastPathComponent().appendingPathComponent("edited.mp4")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exportSession.outputURL = exportPath
        exportSession.outputFileType = .mp4
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    self.addFrameToVideo(exportPath)
                } else if let error = exportSession.error {
                    print("Error al exportar el video: \(error)")
                }
            }
        }
    }

    func addFrameToVideo(_ videoURL: URL) {
        // Método para agregar un marco al video desde la librería de fotos
        let alertController = UIAlertController(title: "Selecciona un Marco", message: "Selecciona un PNG desde la librería para usar como marco.", preferredStyle: .alert)
        let selectFrameAction = UIAlertAction(title: "Seleccionar", style: .default) { [weak self] _ in
            self?.selectFrameImage()
        }
        alertController.addAction(selectFrameAction)
        present(alertController, animated: true, completion: nil)
    }

    func selectFrameImage() {
        library.delegate = self
        library.sourceType = .photoLibrary
        library.mediaTypes = ["public.image"]
        present(library, animated: true, completion: nil)
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let selectedImage = info[.originalImage] as? UIImage else { return }
        // Código para superponer el PNG sobre el video
        dismiss(animated: true, completion: nil)
    }
}

extension ViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if error == nil {
            editVideoInSlowMotion(outputFileURL)
        } else {
            print("Error durante la grabación: \(error?.localizedDescription ?? "Sin descripción de error")")
        }
    }
}
