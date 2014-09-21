//
//  ViewController.swift
//  RealTimeFilter
//
//  Created by ZhangAo on 14-9-20.
//  Copyright (c) 2014年 ZhangAo. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

class ViewController: UIViewController , AVCaptureVideoDataOutputSampleBufferDelegate {
    @IBOutlet var filterButtonsContainer: UIView!
    var captureSession: AVCaptureSession!
    var previewLayer: CALayer!
    var filter: CIFilter!
    lazy var context: CIContext = {
        let eaglContext = EAGLContext(API: EAGLRenderingAPI.OpenGLES2)
        let options = [kCIContextWorkingColorSpace : NSNull()]
        return CIContext(EAGLContext: eaglContext, options: options)
    }()
    lazy var filterNames: [String] = {
        return ["CIColorInvert","CIPhotoEffectMono","CIPhotoEffectInstant","CIPhotoEffectTransfer"]
    }()
    var ciImage: CIImage!
    
    // Video Records
    @IBOutlet var recordsButton: UIButton!
    var assetWriter: AVAssetWriter?
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor?
    var isWriting = false
    var currentSampleTime: CMTime?
    var currentVideoDimensions: CMVideoDimensions?
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewLayer = CALayer()
        // previewLayer.bounds = CGRectMake(0, 0, self.view.frame.size.height, self.view.frame.size.width);
        // previewLayer.position = CGPointMake(self.view.frame.size.width / 2.0, self.view.frame.size.height / 2.0);
        // previewLayer.setAffineTransform(CGAffineTransformMakeRotation(CGFloat(M_PI / 2.0)));
        previewLayer.anchorPoint = CGPointZero
        previewLayer.bounds = view.bounds
        
        filterButtonsContainer.hidden = true
        
        self.view.layer.insertSublayer(previewLayer, atIndex: 0)
        setupCaptureSession()
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        previewLayer.bounds.size = size
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        let captureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        let deviceInput = AVCaptureDeviceInput.deviceInputWithDevice(captureDevice, error: nil) as AVCaptureDeviceInput
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        }
        
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_32BGRA]
        dataOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(dataOutput) {
            captureSession.addOutput(dataOutput)
        }
        
        let queue = dispatch_queue_create("VideoQueue", DISPATCH_QUEUE_SERIAL)
        dataOutput.setSampleBufferDelegate(self, queue: queue)
        
        captureSession.commitConfiguration()
    }

    @IBAction func openCamera(sender: UIButton) {
        sender.enabled = false
        captureSession.startRunning()
        self.filterButtonsContainer.hidden = false
    }
    
    @IBAction func applyFilter(sender: UIButton) {
        var filterName = filterNames[sender.tag]
        filter = CIFilter(name: filterName)
    }
    
    @IBAction func takePicture(sender: UIButton) {
        if ciImage == nil || isWriting {
            return
        }
        sender.enabled = false
        captureSession.stopRunning()

        var cgImage = context.createCGImage(ciImage, fromRect: ciImage.extent())
        ALAssetsLibrary().writeImageToSavedPhotosAlbum(cgImage, metadata: ciImage.properties())
            {(url: NSURL!, error :NSError!) -> Void in
                if error == nil {
                    println("保存成功")
                    println(url)
                } else {
                    let alert = UIAlertView(title: "错误", message: error.localizedDescription, delegate: nil, cancelButtonTitle: "确定")
                    alert.show()
                }
                self.captureSession.startRunning()
                sender.enabled = true
        }
    }
    
    // MARK: - Video Records
    @IBAction func record() {
        if isWriting {
            recordsButton.enabled = false
            assetWriter?.finishWritingWithCompletionHandler({[unowned self] () -> Void in
                println("录制完成")
                self.recordsButton.setTitle("处理中...", forState: UIControlState.Normal)
                self.saveMovieToCameraRoll()
            })
        } else {
            createWriter()
            isWriting = true
            recordsButton.setTitle("停止录制...", forState: UIControlState.Normal)
            assetWriter?.startWriting()
            assetWriter?.startSessionAtSourceTime(currentSampleTime!)
        }
    }
    
    func saveMovieToCameraRoll() {
        ALAssetsLibrary().writeVideoAtPathToSavedPhotosAlbum(movieURL(), completionBlock: { (url: NSURL!, error: NSError?) -> Void in
            if let errorDescription = error?.localizedDescription {
                println("写入视频错误：\(errorDescription)")
            } else {
                self.checkForAndDeleteFile()
                println("写入视频成功")
            }
            self.recordsButton.enabled = true
            self.recordsButton.setTitle("开始录制", forState: UIControlState.Normal)
            self.isWriting = false
        })
    }
    
    func movieURL() -> NSURL {
        var tempDir = NSTemporaryDirectory()
        let urlString = tempDir.stringByAppendingPathComponent("tmpMov.mov")
        return NSURL(fileURLWithPath: urlString)
    }
    
    func checkForAndDeleteFile() {
        let fm = NSFileManager.defaultManager()
        var url = movieURL()
        let exist = fm.fileExistsAtPath(movieURL().absoluteString!)
        
        var error: NSError?
        if exist {
            fm.removeItemAtURL(movieURL(), error: &error)
            println("删除之前的临时文件")
            if let errorDescription = error?.localizedDescription {
                println(errorDescription)
            }
        }
    }
    
    func createWriter() {
        self.checkForAndDeleteFile()
        
        var error: NSError?
        assetWriter = AVAssetWriter(URL: movieURL(), fileType: AVFileTypeQuickTimeMovie, error: &error)
        if let errorDescription = error?.localizedDescription {
            println("创建writer失败")
            println(errorDescription)
            return
        }

        let outputSettings = [
            AVVideoCodecKey : AVVideoCodecH264,
            AVVideoWidthKey : Int(currentVideoDimensions!.width),
            AVVideoHeightKey : Int(currentVideoDimensions!.height)
        ]
        
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        assetWriterVideoInput.transform = CGAffineTransformMakeRotation(CGFloat(M_PI / 2.0))
        
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey : Int(currentVideoDimensions!.width),
            kCVPixelBufferHeightKey : Int(currentVideoDimensions!.height)
        ]
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput,
                                                sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
        
        if assetWriter!.canAddInput(assetWriterVideoInput) {
            assetWriter!.addInput(assetWriterVideoInput)
        } else {
            println("不能添加视频writer的input \(assetWriterVideoInput)")
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(captureOutput: AVCaptureOutput!,didOutputSampleBuffer sampleBuffer: CMSampleBuffer!,fromConnection connection: AVCaptureConnection!) {
        
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        currentVideoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        
        // CVPixelBufferLockBaseAddress(imageBuffer, 0)
        // let width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
        // let height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
        // let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
        // let lumaBuffer = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
        //
        // let grayColorSpace = CGColorSpaceCreateDeviceGray()
        // let context = CGBitmapContextCreate(lumaBuffer, width, height, 8, bytesPerRow, grayColorSpace, CGBitmapInfo.allZeros)
        // let cgImage = CGBitmapContextCreateImage(context)

        var outputImage = CIImage(CVPixelBuffer: imageBuffer)
        
        if filter != nil {
            filter.setValue(outputImage, forKey: kCIInputImageKey)
            outputImage = filter.outputImage
        }
        
        if isWriting {
            if assetWriterPixelBufferInput?.assetWriterInput.readyForMoreMediaData == true {
                autoreleasepool {
                    var newPixelBuffer: Unmanaged<CVPixelBuffer>? = nil
                    CVPixelBufferPoolCreatePixelBuffer(nil, self.assetWriterPixelBufferInput?.pixelBufferPool, &newPixelBuffer)
                    
                    self.context.render(outputImage, toCVPixelBuffer: newPixelBuffer?.takeUnretainedValue(), bounds: outputImage.extent(), colorSpace: nil)
                    
                    let success = self.assetWriterPixelBufferInput?.appendPixelBuffer(newPixelBuffer?.takeUnretainedValue(), withPresentationTime: self.currentSampleTime!)
                    
                    newPixelBuffer?.release()
                    
                    if success == false {
                        println("Pixel Buffer没有附加成功")
                    }
                }
            }
        }
        
        let orientation = UIDevice.currentDevice().orientation
        var t: CGAffineTransform!
        if orientation == UIDeviceOrientation.Portrait {
            t = CGAffineTransformMakeRotation(CGFloat(-M_PI / 2.0))
        } else if orientation == UIDeviceOrientation.PortraitUpsideDown {
            t = CGAffineTransformMakeRotation(CGFloat(M_PI / 2.0))
        } else if (orientation == UIDeviceOrientation.LandscapeRight) {
            t = CGAffineTransformMakeRotation(CGFloat(M_PI))
        } else {
            t = CGAffineTransformMakeRotation(0)
        }
        outputImage = outputImage.imageByApplyingTransform(t)
        
        let cgImage = context.createCGImage(outputImage, fromRect: outputImage.extent())
        ciImage = outputImage
        
        dispatch_sync(dispatch_get_main_queue(), {
            self.previewLayer.contents = cgImage
        })
    }
}
