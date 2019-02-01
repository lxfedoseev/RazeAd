/**
 * Copyright (c) 2018 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import SceneKit
import ARKit
import Vision

class AdViewController: UIViewController {
  @IBOutlet var sceneView: ARSCNView!
  weak var targetView: TargetView!
  
  private var billboard: BillboardContainer?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Set the view's delegate
    sceneView.delegate = self
    
    // Set the session's delegate
    sceneView.session.delegate = self

    // Show statistics such as fps and timing information
    sceneView.showsStatistics = true
    
    // Create a new scene
    let scene = SCNScene()
    
    // Set the scene to the view
    sceneView.scene = scene
    
    // Setup the target view
    let targetView = TargetView(frame: view.bounds)
    view.addSubview(targetView)
    self.targetView = targetView
    targetView.show()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    // Create a session configuration
    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .camera
    
    // Run the view's session
    sceneView.session.run(configuration)
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    
    // Pause the view's session
    sceneView.session.pause()
  }
}

// MARK: - ARSCNViewDelegate
extension AdViewController: ARSCNViewDelegate {
  func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
    guard let billboard = billboard else { return nil }
    var node: SCNNode? = nil
    //DispatchQueue.main.sync {
    switch anchor {
    case billboard.billboardAnchor:
      let billboardNode = addBillboardNode()
      node = billboardNode
        
    case (let videoAnchor)
        where videoAnchor == billboard.videoAnchor:
        node = addVideoPlayerNode()
    default:
      break
    }
    
    return node
  }
}

extension AdViewController: ARSessionDelegate {
  func session(_ session: ARSession, didFailWithError error: Error) {
  }
  
  func sessionWasInterrupted(_ session: ARSession) {
    removeBillboard()
  }
  
  func sessionInterruptionEnded(_ session: ARSession) {
  }
}

extension AdViewController {
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    // 1
    if billboard?.hasVideoNode == true {
        // 2
        billboard?.billboardNode?.isHidden = false
        // 3
        removeVideo()
        // 4
        return
    }
    
    guard let currentFrame = sceneView.session.currentFrame else { return }
    
    DispatchQueue.global(qos: .background).async {
      do {
        let request = VNDetectBarcodesRequest { (request, error) in
          // Access the first result in the array,
          // after converting to an array
          // of VNBarcodeObservation
          guard let results = request.results?.compactMap({ $0 as? VNBarcodeObservation }), let result = results.first else {
            print ("[Vision] VNRequest produced no result")
            return
          }
          
          let coordinates: [matrix_float4x4] = [result.topLeft, result.topRight, result.bottomRight, result.bottomLeft].compactMap {
            guard let hitFeature = currentFrame.hitTest($0, types: .featurePoint).first else { return nil }
            return hitFeature.worldTransform
          }
          
          guard coordinates.count == 4 else { return }
          
          DispatchQueue.main.async {
            self.removeBillboard()
            
            let (topLeft, topRight, bottomRight, bottomLeft) = (coordinates[0], coordinates[1], coordinates[2], coordinates[3])
            
            self.createBillboard(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
            
            /*
            for coordinate in coordinates {
              let box = SCNBox(width: 0.01, height: 0.01, length: 0.001, chamferRadius: 0.0)
              let node = SCNNode(geometry: box)
              node.transform = SCNMatrix4(coordinate)
              self.sceneView.scene.rootNode.addChildNode(node)
            }
            */
          }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: currentFrame.capturedImage)
        try handler.perform([request])
      } catch(let error) {
        print("An error occurred during rectangle detection: \(error)")
      }
    }
  }
}

private extension AdViewController {
  func createBillboard(topLeft: matrix_float4x4, topRight: matrix_float4x4, bottomRight: matrix_float4x4, bottomLeft: matrix_float4x4) {
    let plane = RectangularPlane(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
    // 1
    let rotation =
        SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 0.0, 1.0)
    // 2
    let rotatedCenter =
        plane.center * matrix_float4x4(rotation)
    let anchor = ARAnchor(transform: rotatedCenter)
    billboard = BillboardContainer(billboardAnchor: anchor, plane: plane)
    sceneView.session.add(anchor: anchor)
    
    print("New billboard created")
  }
    
    func createVideo() {
        guard let billboard = self.billboard else { return }
        let rotation =
            SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 0.0, 1.0)
        let rotatedCenter =
            billboard.plane.center * matrix_float4x4(rotation)
        // 1
        let anchor = ARAnchor(transform: rotatedCenter)
        // 2
        sceneView.session.add(anchor: anchor)
        // 3
        self.billboard?.videoAnchor = anchor
    }
  
  func addBillboardNode() -> SCNNode? {
    guard let billboard = billboard else { return nil }
    
    let rectangle = SCNPlane(width: billboard.plane.width, height: billboard.plane.height)
    let rectangleNode = SCNNode(geometry: rectangle)
    self.billboard?.billboardNode = rectangleNode
    
    let images = [
        "logo_1", "logo_2", "logo_3", "logo_4", "logo_5"
        ].map { UIImage(named: $0)! }
    setBillboardImages(images)
    
    return rectangleNode
  }
    
    func addVideoPlayerNode() -> SCNNode? {
        guard let billboard = self.billboard else { return nil }
        // 1
        let billboardSize = CGSize(width: billboard.plane.width,
                                   height: billboard.plane.height / 2
        )
        let frameSize = CGSize(width: 1024, height: 512)
        let videoUrl = URL(string:
            "https://www.rmp-streaming.com/media/bbb-360p.mp4")!
        // 2
        let player = AVPlayer(url: videoUrl)
        let videoPlayerNode = SKVideoNode(avPlayer: player)
        videoPlayerNode.size = frameSize
        videoPlayerNode.position = CGPoint(
            x: frameSize.width / 2,
            y: frameSize.height / 2
        )
        videoPlayerNode.zRotation = CGFloat.pi
        // 3
        let spritekitScene = SKScene(size: frameSize)
        spritekitScene.addChild(videoPlayerNode)
        // 4
        let plane = SCNPlane(
            width: billboardSize.width,
            height: billboardSize.height
        )
        plane.firstMaterial!.isDoubleSided = true
        plane.firstMaterial!.diffuse.contents = spritekitScene
        let node = SCNNode(geometry: plane)
        // 5
        self.billboard?.videoNode = node
        // 6
        self.billboard?.billboardNode?.isHidden = true
        videoPlayerNode.play()
        return node
    }
    
  
  func removeBillboard() {
    if let anchor = billboard?.billboardAnchor {
      sceneView.session.remove(anchor: anchor)
      billboard?.billboardNode?.removeFromParentNode()
      billboard = nil
    }
  }
    
    func removeVideo() {
        if let videoAnchor = billboard?.videoAnchor {
            // 1
            sceneView.session.remove(anchor: videoAnchor)
            // 2
            billboard?.videoNode?.removeFromParentNode()
            // 3
            billboard?.videoAnchor = nil
            billboard?.videoNode = nil
        }
    }
    
    
    func setBillboardImages(_ images: [UIImage]) {
        // 1
        let material = SCNMaterial()
        // 2
        material.isDoubleSided = true
        // 3
        DispatchQueue.main.async {
            // https://forums.developer.apple.com/thread/89423
            // A UIView can be assigned to a material
            // 4
            // 1
            let billboardViewController = BillboardViewController(
                nibName: "BillboardViewController", bundle: nil)
            billboardViewController.delegate = self
            // 2
            billboardViewController.images = images
            // 3
            material.diffuse.contents = billboardViewController.view
            self.billboard?.viewController = billboardViewController
            // 5
            self.billboard?.billboardNode?
                .geometry?.materials = [material]
        }
    }
    
}

extension AdViewController: BillboardViewDelegate {
    func billboardViewDidSelectPlayVideo(
        _ view: BillboardView) {
        createVideo()
    }
}
