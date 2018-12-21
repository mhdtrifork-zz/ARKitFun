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
        
        switch anchor {
        case billboard.billboardAnchor:
            let billboardNode = addBillboardNode()
            node = billboardNode
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
    guard let currentFrame = sceneView.session.currentFrame else { return }
    
    DispatchQueue.global(qos: .background).async {
        do {
            let request = VNDetectRectanglesRequest(completionHandler: { (request, error) in
                guard let result = request.results?.compactMap({ $0 as? VNRectangleObservation }).first else {
                    print ("[Vision] VNRequest produced no result")
                    return
                }
                let coordinates: [matrix_float4x4] = [
                    result.topLeft,
                    result.topRight,
                    result.bottomRight,
                    result.bottomLeft].compactMap {
                        guard let hitFeature = currentFrame.hitTest( $0, types: .featurePoint).first else { return nil }
                        return hitFeature.worldTransform
                    }
                guard coordinates.count == 4 else { return }
                
                DispatchQueue.main.async {
                    self.removeBillboard()
                    
                    self.createBillboard(topLeft: coordinates[0], topRight: coordinates[1],
                        bottomRight: coordinates[2], bottomLeft: coordinates[3])
                    
                    for coordinate in coordinates {
                        let box = SCNBox(width: 0.01, height: 0.01, length: 0.001, chamferRadius: 0.0)
                        let node = SCNNode(geometry: box)
                        node.transform = SCNMatrix4(coordinate)
                        self.sceneView.scene.rootNode.addChildNode(node)
                    }
                }
            })
            
            let handler = VNImageRequestHandler(cvPixelBuffer: currentFrame.capturedImage)
            
            try handler.perform([request])
        } catch(let error) {
            print("An error occurred during rectangle detection: \(error)")
        }
    }
  }
}

private extension AdViewController {
    func createBillboard(
        topLeft: matrix_float4x4, topRight: matrix_float4x4,
        bottomRight: matrix_float4x4, bottomLeft: matrix_float4x4) {
        
        // 1
        let plane = RectangularPlane(
            topLeft: topLeft, topRight: topRight,
            bottomLeft: bottomLeft, bottomRight: bottomRight)
        
        // 2
        let anchor = ARAnchor(transform: plane.center)
        
        // 3
        billboard = BillboardContainer(billboardAnchor: anchor, plane: plane)
        
        // 4
        sceneView.session.add(anchor: anchor)
        
        print("New billboard created")
    }
    
    func removeBillboard() {
        // 1
        if let anchor = billboard?.billboardAnchor {
            // 2
            sceneView.session.remove(anchor: anchor)
            // 3
            billboard?.billboardNode?.removeFromParentNode()
            billboard = nil
        }
    }
    
    func addBillboardNode() -> SCNNode? {
        guard let billboard = billboard else { return nil }
        let rectangle = SCNPlane(width: billboard.plane.width, height: billboard.plane.height)
        let rectangleNode = SCNNode(geometry: rectangle)
        self.billboard?.billboardNode = rectangleNode
        return rectangleNode
    }
}
