//
//  main.swift
//  movespace
//
//  Created by 张朝杰 on 2021/11/10.
//

import AppKit

let action = CommandLine.argc > 1 ? CommandLine.arguments[1] : nil
let params = CommandLine.argc > 2 ? CommandLine.arguments[2] : nil


func signalHandler(_: Int32) -> Void {
    // print(Thread.callStackSymbols)
}

signal(SIGABRT, signalHandler);
signal(SIGILL, signalHandler);
signal(SIGINT, signalHandler);
signal(SIGSEGV, signalHandler);
signal(SIGTRAP, signalHandler);

func displayNotification(message: String) -> Void {
    print(message)
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", "display notification \"\(message)\""]
    task.launch()
}

@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_: Int) -> Int
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int
@_silgen_name("CGSCopySpaces") func CGSCopySpaces(_: Int, _: Int) -> CFArray
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_: Int, _: Int, _: CFArray) -> CFArray
@_silgen_name("CGSRemoveWindowsFromSpaces") func CGSRemoveWindowsFromSpaces(_: Int, _: CFArray, _: CFArray) -> Void
@_silgen_name("CGSAddWindowsToSpaces") func CGSAddWindowsToSpaces(_: Int, _: CFArray, _: CFArray) -> Void

let kCGSAllSpacesMask = 1 << 0 | 1 << 1 | 1 << 2

func currentSpaces() -> [Int] {
    let allSpaces = CGSCopySpaces(CGSMainConnectionID(), kCGSAllSpacesMask) as! [Int]
    print("allSpaces:", allSpaces)

    let innerSpaces = (UserDefaults.standard.array(forKey: "innerSpaces") ?? []) as! [Int]
    print("innerSpaces:", innerSpaces)
    
    let outterSpaces = allSpaces.filter({!innerSpaces.contains($0)})
    print("outterSpaces:", outterSpaces)

    let currentSpaceID = CGSGetActiveSpace(CGSMainConnectionID())
    print("currentSpaceID:", currentSpaceID)
    
    let currentSpaces = innerSpaces.contains(currentSpaceID) ? innerSpaces : outterSpaces
    print("currentSpaces:", currentSpaces)
    return currentSpaces
}

if action == "left" || action == "right" {
    guard UserDefaults.standard.array(forKey: "innerSpaces") != nil else {
        displayNotification(message: "movespace reset")
        exit(1)
    }

    let direction = action == "left" ? -1 : 1
    print("direction:", direction)
    
    let currentTimestamp = Date().timeIntervalSince1970
    print("currentTimestamp:", currentTimestamp)

    let moveWindowID: Int = {
        if currentTimestamp - UserDefaults.standard.double(forKey: "timestamp") < 1.0 {
            return UserDefaults.standard.integer(forKey: "windowID")
        } else {
            let currentWindow = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]).first(where: {$0["kCGWindowLayer"] as! Int == 0})
            guard currentWindow != nil else {
                displayNotification(message: "currentWindow == nil")
                exit(1)
            }
            return currentWindow!["kCGWindowNumber"] as! Int
        }
    }()
    print("moveWindowID:", moveWindowID)
    
    // TODO 越界
    let moveWindowSpaceID = (CGSCopySpacesForWindows(CGSMainConnectionID(), kCGSAllSpacesMask, [moveWindowID] as CFArray) as! [Int])[0]
    print("moveWindowSpaceID:", moveWindowSpaceID)
    
    let currentSpaces = currentSpaces()
    
    let moveWindowSpaceIndex = currentSpaces.firstIndex(of: moveWindowSpaceID)
    guard moveWindowSpaceIndex != nil else {
        displayNotification(message: "moveWindowSpaceIndex == nil")
        exit(1)
    }
    
    let targetSpaceIndex = moveWindowSpaceIndex! + direction
    print("targetSpaceIndex:", targetSpaceIndex)
    
    if targetSpaceIndex >= 0 && targetSpaceIndex < currentSpaces.count {
        let targetSpaceID = currentSpaces[targetSpaceIndex]
        print("targetSpaceID:", targetSpaceID)
        
        CGSAddWindowsToSpaces(CGSMainConnectionID(), [moveWindowID] as CFArray, [targetSpaceID] as CFArray)
        CGSRemoveWindowsFromSpaces(CGSMainConnectionID(), [moveWindowID] as CFArray, [moveWindowSpaceID] as CFArray)
    }
    UserDefaults.standard.set(currentTimestamp, forKey: "timestamp")
    UserDefaults.standard.set(moveWindowID, forKey: "windowID")
} else if action == "down" {
    let moveWindowID = UserDefaults.standard.integer(forKey: "windowID")
    print("moveWindowID:", moveWindowID)
    
    // TODO 越界
    let moveWindowSpaceID = (CGSCopySpacesForWindows(CGSMainConnectionID(), kCGSAllSpacesMask, [moveWindowID] as CFArray) as! [Int])[0]
    print("moveWindowSpaceID:", moveWindowSpaceID)
    
    let currentSpaceID = CGSGetActiveSpace(CGSMainConnectionID())
    print("currentSpaceID:", currentSpaceID)
    
    if currentSpaceID != moveWindowSpaceID {
        CGSAddWindowsToSpaces(CGSMainConnectionID(), [moveWindowID] as CFArray, [currentSpaceID] as CFArray)
        CGSRemoveWindowsFromSpaces(CGSMainConnectionID(), [moveWindowID] as CFArray, [moveWindowSpaceID] as CFArray)
    }
    
    UserDefaults.standard.set(moveWindowID, forKey: "windowID")
} else if action == "reset" {
    UserDefaults.standard.dictionaryRepresentation().forEach { (key: String, _: Any) in
        UserDefaults.standard.removeObject(forKey: key)
    }
    var count = 0
    var lastSpaceID = 0
    var innerSpaces: [Int] = []
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        if count < 25 {
            let currentSpaceID = CGSGetActiveSpace(CGSMainConnectionID())
            if lastSpaceID != currentSpaceID {
                displayNotification(message: String(currentSpaceID))
                lastSpaceID = currentSpaceID
                count = 0
            }
            if !innerSpaces.contains(currentSpaceID) {
                innerSpaces.append(currentSpaceID)
            }
            count += 1
        } else {
            displayNotification(message: "innerSpaces: " + innerSpaces.description)
            UserDefaults.standard.set(innerSpaces, forKey: "innerSpaces")
            exit(0)
        }
    }
    RunLoop.current.run()
} else if action == "mouse" {
    let inMain = NSEvent.mouseLocation.y < NSPointInRect(NSEvent.mouseLocation, NSRect(x: 0, y: 0, width: (NSScreen.main?.frame.size.width)!, height: (NSScreen.main?.frame.size.height)!))
    let mainDisplayID = CGMainDisplayID()
    for screen in NSScreen.screens {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")]! as! CGDirectDisplayID
        if NSScreen.screens.count == 1 || inMain && mainDisplayID != displayID || !inMain && mainDisplayID == displayID {
            let frameSize = screen.frame.size
            CGDisplayMoveCursorToPoint(displayID, CGPoint(x: frameSize.width / 2, y: frameSize.height / 2))
            exit(0)
        }
    }
} else {
    let _ = currentSpaces()
    print("movespace left")
    print("movespace right")
    print("movespace down")
    print("movespace reset")
    print("movespace mouse")
}
