import CoreMedia
import AVFoundation
import AVKit
import CoreML
import UIKit
import Vision
import AssetsLibrary
import Photos

class ViewController: UIViewController {

  @IBOutlet var videoPreview: UIView!
  @IBOutlet weak var recordButton: UIButton!

  var videoCapture: VideoCapture!
  var currentBuffer: CVPixelBuffer?
    
    var videoDataOutput: AVCaptureVideoDataOutput?
    var assetWriter: AVAssetWriter?
    var assetWriterInput: AVAssetWriterInput?
    var filePath: URL?
    var sessionAtSourceTime: CMTime?

  let coreMLModel = MobileNetV2_SSDLite()

  lazy var visionModel: VNCoreMLModel = {
    do {
      return try VNCoreMLModel(for: coreMLModel.model)
    } catch {
      fatalError("Failed to create VNCoreMLModel: \(error)")
    }
  }()

  lazy var visionRequest: VNCoreMLRequest = {
    let request = VNCoreMLRequest(model: visionModel, completionHandler: {
      [weak self] request, error in
      self?.processObservations(for: request, error: error)
    })

    // NOTE: If you use another crop/scale option, you must also change
    // how the BoundingBoxView objects get scaled when they are drawn.
    // Currently they assume the full input image is used.
    request.imageCropAndScaleOption = .scaleFill
    return request
  }()
    
    var recording = false {
        didSet {
            recording ? self.start() : self.stop()
        }
    }

  let maxBoundingBoxViews = 10
  var boundingBoxViews = [BoundingBoxView]()
  var colors: [String: UIColor] = [:]
    
    let debouncer = Debouncer(label: "123", interval: 2000)

  override func viewDidLoad() {
    super.viewDidLoad()
    setUpBoundingBoxViews()
    setUpCamera()
      self.authorize()
  }

  func setUpBoundingBoxViews() {
    for _ in 0..<maxBoundingBoxViews {
      boundingBoxViews.append(BoundingBoxView())
    }

    // The label names are stored inside the MLModel's metadata.
    guard let userDefined = coreMLModel.model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String],
       let allLabels = userDefined["classes"] else {
      fatalError("Missing metadata")
    }

    let labels = allLabels.components(separatedBy: ",")

    // Assign random colors to the classes.
    for label in labels {
      colors[label] = UIColor(red: CGFloat.random(in: 0...1),
                              green: CGFloat.random(in: 0...1),
                              blue: CGFloat.random(in: 0...1),
                              alpha: 1)
    }
  }
    
    func authorize()->Bool{
            let status = PHPhotoLibrary.authorizationStatus()
             
            switch status {
            case .authorized:
                return true
                 
            case .notDetermined:
                
                PHPhotoLibrary.requestAuthorization({ (status) -> Void in
                    DispatchQueue.main.async(execute: { () -> Void in
                        _ = self.authorize()
                    })
                })
                 
            default: ()
            DispatchQueue.main.async(execute: { () -> Void in
                let alertController = UIAlertController(title: "要求權限",
                                                        message: "允許訪問照片",
                                                        preferredStyle: .alert)
                 
                let cancelAction = UIAlertAction(title:"取消", style: .cancel, handler:nil)
                 
                let settingsAction = UIAlertAction(title:"設定", style: .default, handler: {
                    (action) -> Void in
                    let url = URL(string: UIApplication.openSettingsURLString)
                    if let url = url, UIApplication.shared.canOpenURL(url) {
                        if #available(iOS 10, *) {
                            UIApplication.shared.open(url, options: [:],
                                                      completionHandler: {
                                                        (success) in
                            })
                        } else {
                           UIApplication.shared.openURL(url)
                        }
                    }
                })
                alertController.addAction(cancelAction)
                alertController.addAction(settingsAction)
                self.present(alertController, animated: true, completion: nil)
            })
            }
            return false
        }

  func setUpCamera() {
    videoCapture = VideoCapture()
    videoCapture.delegate = self

    videoCapture.setUp(sessionPreset: .hd1280x720) { success in
      if success {
        // Add the video preview into the UI.
        if let previewLayer = self.videoCapture.previewLayer {
          self.videoPreview.layer.addSublayer(previewLayer)
          self.resizePreviewLayer()
        }

        // Add the bounding box layers to the UI, on top of the video preview.
        for box in self.boundingBoxViews {
          box.addToLayer(self.videoPreview.layer)
        }

        // Once everything is set up, we can start capturing live video.
        self.videoCapture.start()
      }
    }
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    resizePreviewLayer()
  }

  func resizePreviewLayer() {
    videoCapture.previewLayer?.frame = videoPreview.bounds
  }

  func predict(sampleBuffer: CMSampleBuffer) {
    if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      currentBuffer = pixelBuffer

      // Get additional info from the camera.
      var options: [VNImageOption : Any] = [:]
      if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
        options[.cameraIntrinsics] = cameraIntrinsicMatrix
      }

      let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: options)
      do {
        try handler.perform([self.visionRequest])
      } catch {
        print("Failed to perform Vision request: \(error)")
      }

      currentBuffer = nil
    }
  }

  func processObservations(for request: VNRequest, error: Error?) {
    DispatchQueue.main.async {
      if let results = request.results as? [VNRecognizedObjectObservation] {
        self.show(predictions: results)
      } else {
        self.show(predictions: [])
      }
    }
  }

  func show(predictions: [VNRecognizedObjectObservation]) {
    for i in 0..<boundingBoxViews.count {
      if i < predictions.count {
        let prediction = predictions[i]

        /*
         The predicted bounding box is in normalized image coordinates, with
         the origin in the lower-left corner.

         Scale the bounding box to the coordinate system of the video preview,
         which is as wide as the screen and has a 16:9 aspect ratio. The video
         preview also may be letterboxed at the top and bottom.

         Based on code from https://github.com/Willjay90/AppleFaceDetection

         NOTE: If you use a different .imageCropAndScaleOption, or a different
         video resolution, then you also need to change the math here!
        */

        let width = videoPreview.bounds.width
        let height = width * 16 / 9
        let offsetY = (videoPreview.bounds.height - height) / 2
        let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
        let rect = prediction.boundingBox.applying(scale).applying(transform)

        // The labels array is a list of VNClassificationObservation objects,
        // with the highest scoring class first in the list.
        let bestClass = prediction.labels[0].identifier
        let confidence = prediction.labels[0].confidence
          
          if (bestClass == "person")
          {
              if recordButton.titleLabel?.text == "Record" {
                  recording.toggle()
              }
              debouncer.call { // 防止連續處發
                  DispatchQueue.main.async {
                      self.recording.toggle()
                  }
              }
          }

        // Show the bounding box.
        let label = String(format: "%@ %.1f", bestClass, confidence * 100)
        let color = colors[bestClass] ?? UIColor.red
        boundingBoxViews[i].show(frame: rect, label: label, color: color)
      } else {
        boundingBoxViews[i].hide()
      }
    }
  }
    
    func start() {
        self.recordButton.setTitle("Stop", for: .normal)
        self.sessionAtSourceTime = nil
        self.setUpWriter()
        switch self.assetWriter?.status {
        case .writing:
            print("status writing")
        case .failed:
            print("status failed")
        case .cancelled:
            print("status cancelled")
        case .unknown:
            print("status unknown")
        default:
            print("status completed")
        }

    }

    func stop() {
        self.recordButton.setTitle("Record", for: .normal)
        self.assetWriterInput?.markAsFinished()
        print("marked as finished")
        
        self.assetWriter?.finishWriting { [weak self] in
            self?.sessionAtSourceTime = nil
            
            if (self?.filePath != nil)
            {
                guard let outputUrl = self?.filePath else { return }

                PHPhotoLibrary.shared().saveVideo(outputUrl, albumName: "test") { (asset, error) in
                    if error != nil {
                        return
                    }
                    do {
                        try FileManager.default.removeItem(at: outputUrl)
                    }
                    catch {
                        print(error)
                    }
                }
            }
        }
        print("finished writing \(String(describing: self.filePath?.path))")
    }
    
    func setUpWriter() {
        do {
            filePath = videoFileLocation()
            assetWriter = try AVAssetWriter(outputURL: filePath!, fileType: AVFileType.mov)

            // add video input
            let settings = self.videoDataOutput?.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey : AVVideoCodecType.h264,
            AVVideoWidthKey : 720,
            AVVideoHeightKey : 1280,
            AVVideoCompressionPropertiesKey : [
                AVVideoAverageBitRateKey : 2300000,
                ],
            ])
            guard let assetWriterInput = assetWriterInput, let assetWriter = assetWriter else { return }
            assetWriterInput.expectsMediaDataInRealTime = true
            
            if assetWriter.canAdd(assetWriterInput) {
                assetWriter.add(assetWriterInput)
                print("asset input added")
            } else {
                print("no input added")
            }

            assetWriter.startWriting()
            
            self.assetWriter = assetWriter
            self.assetWriterInput = assetWriterInput
        } catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    func videoFileLocation() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent("videoFile")).appendingPathExtension("mov")
        do {
        if FileManager.default.fileExists(atPath: videoOutputUrl.path) {
            try FileManager.default.removeItem(at: videoOutputUrl)
            print("file removed")
        }
        } catch {
            print(error)
        }

        return videoOutputUrl
    }
    
    func canWrite() -> Bool {
        return recording && assetWriter != nil && assetWriter?.status == .writing
    }
    
// MARK: - Click Event
    
    @IBAction func startStopClicked(_ sender: Any) {
        recording.toggle()
    }
    
    @IBAction func play(_ sender: Any) {//播放MP4影片

         let player = AVPlayer(url: Bundle.main.url(forResource: "worker-zone-detection", withExtension: "mp4")!)
        
        let playerController = AVPlayerViewController()
        playerController.player = player
        present(playerController, animated: true) {
            player.play()
        }
    }
    
}


// MARK: - VideoCaptureDelegate

extension ViewController: VideoCaptureDelegate {
  func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
      
      
      predict(sampleBuffer: sampleBuffer)
      guard self.recording else { return }
      
      let writable = self.canWrite()

      if writable, self.sessionAtSourceTime == nil {
          // start writing
          sessionAtSourceTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
          self.assetWriter?.startSession(atSourceTime: sessionAtSourceTime!)
      }
      guard let assetWriterInput = self.assetWriterInput else { return }
      if writable, assetWriterInput.isReadyForMoreMediaData {
          assetWriterInput.append(sampleBuffer)
      }
  }
    
    
    func convert(cmage: CIImage) -> UIImage { // 在image上畫框用 沒做完
         let context = CIContext(options: nil)
         let cgImage = context.createCGImage(cmage, from: cmage.extent)!
         let image = UIImage(cgImage: cgImage)
        
        return self.imageWith(radius: videoPreview.frame.height, borderWidth: videoPreview.frame.width, borderColor: UIColor.green, image: image, centerIconSize: videoPreview.frame.size)!
    }
    
    
     func imageWith(radius: CGFloat, borderWidth: CGFloat, borderColor: UIColor, image: UIImage, resultImageSize: CGSize = CGSize.zero, centerIconSize: CGSize) -> UIImage? {
            var size = CGSize.zero
            if resultImageSize == CGSize.zero {
                size = CGSize(width: image.size.width+2*borderWidth, height: image.size.height+2*borderWidth)
            }else {
                size = CGSize(width: resultImageSize.width+2*borderWidth, height: resultImageSize.height+2*borderWidth)
            }
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let path = UIBezierPath(roundedRect: CGRect(origin: CGPoint.zero, size: size), cornerRadius: radius+borderWidth/2)
            borderColor.set()
            path.addClip()
            path.stroke()
            let clipPath = UIBezierPath(roundedRect: CGRect(x: borderWidth, y: borderWidth, width: size.width-2*borderWidth, height: size.height-2*borderWidth), cornerRadius: radius)
            clipPath.addClip()
            image.draw(in: CGRect(origin: CGPoint(x: borderWidth+(size.width-2*borderWidth-centerIconSize.width)/2, y: borderWidth+(size.height-2*borderWidth-centerIconSize.height)/2), size: centerIconSize))
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return newImage
    }
}



