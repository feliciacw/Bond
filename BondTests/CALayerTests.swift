//
//  CALayerTests.swift
//  Bond
//
//  Created by Tony Arnold on 16/04/2015.
//  Copyright (c) 2015 Bond. All rights reserved.
//

import Bond
import QuartzCore
import XCTest

#if os(iOS)
  import UIKit
  typealias Color = UIColor
  #else
  import AppKit
  typealias Color = NSColor
#endif

class CALayerTests: XCTestCase {
  
  func testCALayerBackgroundColorBond() {
    let driver = Observable<CGColor>(Color.whiteColor().CGColor)
    let layer = CALayer()

    layer.backgroundColor = Color.red().cgColor
    XCTAssert((layer.backgroundColor?.equalTo(Color.red().cgColor))!, "Initial value")
    
    driver.bindTo(layer.bnd_backgroundColor)
    XCTAssert((layer.backgroundColor?.equalTo(Color.white().cgColor))!, "Value after binding")
    
    driver.value = Color.greenColor().CGColor
    XCTAssert((layer.backgroundColor?.equalTo(Color.green().cgColor))!, "Value after dynamic change")
  }
  
}
