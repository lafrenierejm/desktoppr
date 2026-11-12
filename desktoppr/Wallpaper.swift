//
//  Wallpaper.swift
//  desktoppr
//

/*    Copyright 2018 Armin Briegel, Scripting OS X

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import AppKit
import Foundation

/// Prints a line to standard error.
func errprint(_ error: String) {
  FileHandle.standardError.write(Data((error + "\n").utf8))
}

func download(from url: URL) -> String? {
  //  var headRequest = URLRequest(url: url)
  //  headRequest.httpMethod = "HEAD"
  //  let headSemaphore = DispatchSemaphore(value: 0)
  //  let headerTask = URLSession.shared.dataTask(with: headRequest) { _, response, error in
  //    defer { headSemaphore.signal() }
  //
  //    if let httpResponse = response as? HTTPURLResponse {
  //      print("http response code: \(httpResponse.statusCode)")
  //      print("header fields: \(httpResponse.allHeaderFields)")
  //    }
  //    print(response?.suggestedFilename)
  //  }
  //  headerTask.resume()
  //  headSemaphore.wait()

  let request = URLRequest(url: url)
  var newImage: URL? = nil
  let semaphore = DispatchSemaphore(value: 0)

  let downloadTask = URLSession.shared.downloadTask(with: request) {
    downloadedPicture, response, error in
    defer { semaphore.signal() }

    guard let downloadedPicture = downloadedPicture else { return }
    let filename = response?.suggestedFilename ?? downloadedPicture.lastPathComponent
    guard
      let applicationSupportDir = try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else { return }
    let desktopprSupportDir = applicationSupportDir.appendingPathComponent(
      "desktoppr", isDirectory: true)
    if !FileManager.default.fileExists(atPath: desktopprSupportDir.path) {
      do {
        try FileManager.default.createDirectory(
          at: desktopprSupportDir, withIntermediateDirectories: true, attributes: nil)
      } catch {
        return
      }
    }
    let newURL = desktopprSupportDir.appendingPathComponent(filename)
    do {
      if FileManager.default.fileExists(atPath: newURL.path) {
        try FileManager.default.removeItem(at: newURL)
      }
      try FileManager.default.moveItem(at: downloadedPicture, to: newURL)
    } catch {
      return
    }
    newImage = newURL
  }

  downloadTask.resume()
  semaphore.wait()
  return newImage?.path
}

/// Resolves a file path or an http(s) URL to a local file, downloading if needed.
func resolvePicture(_ path: String) throws -> URL {
  let fm = FileManager.default
  var imagePath = path

  if path.starts(with: "http://") || path.starts(with: "https://") {
    guard let url = URL(string: path), let downloadedImagePath = download(from: url) else {
      throw RuntimeError("couldn't download: \(path)")
    }
    imagePath = downloadedImagePath
    Defaults.lastURL = path
  }

  let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
  let url = URL(fileURLWithPath: imagePath, relativeTo: cwd)
  guard fm.fileExists(atPath: url.path) else {
    throw RuntimeError("no file: \(path)")
  }
  return url
}

func desktopImagePath(for screen: NSScreen) -> String {
  let ws = NSWorkspace.shared
  return ws.desktopImageURL(for: screen)!.path
}

func setAllDesktopImages(url: URL, allSpaces: Bool = false) throws {
  for screen in NSScreen.screens {
    setDesktopImage(url: url, for: screen)
  }

  Defaults.lastPath = url.path
  Defaults.lastSetDate = Date()

  if allSpaces {
    do {
      try WallpaperStore.spread(image: url)
    } catch {
      throw RuntimeError("could not set the picture for all spaces: \(error)")
    }
  }
}

func setDesktopImage(url: URL, for screen: NSScreen) {
  let ws = NSWorkspace.shared
  try! ws.setDesktopImageURL(url, for: screen)
}

func setFillColor(color: NSColor) {
  let ws = NSWorkspace.shared
  // loop through all screens
  for screen in NSScreen.screens {
    let currentImageURL = ws.desktopImageURL(for: screen)
    var options = ws.desktopImageOptions(for: screen)
    options![NSWorkspace.DesktopImageOptionKey.fillColor] = color
    try! ws.setDesktopImageURL(currentImageURL!, for: screen, options: options!)
  }
}

func fillColor(for screen: NSScreen) -> String? {
  let ws = NSWorkspace.shared
  guard let options = ws.desktopImageOptions(for: screen) else { return nil }
  guard let fillColor = options[NSWorkspace.DesktopImageOptionKey.fillColor] as? NSColor else {
    return nil
  }

  let redByte = Int(fillColor.redComponent * 0xff)
  let greenByte = Int(fillColor.greenComponent * 0xff)
  let blueByte = Int(fillColor.blueComponent * 0xff)

  let hexString = String(format: "%02X%02X%02X", redByte, greenByte, blueByte)

  return hexString
}

// key never seems to be set in the image options
func allowClipping(for screen: NSScreen) -> Bool? {
  let ws = NSWorkspace.shared
  guard let options = ws.desktopImageOptions(for: screen) else { return nil }
  guard let clip = options[NSWorkspace.DesktopImageOptionKey.allowClipping] as? NSNumber else {
    return false
  }

  return clip.boolValue
}

// values map to the settings in Desktop pref pane as following:
// 0: (no value set in dict) Fill Screen
// 1: Stretch to Fill Screen
// 2: Center
// 3: Fit to Screen

func setImageScaling(_ scale: ScaleOption) {
  let ws = NSWorkspace.shared
  let scaleValue: NSNumber?
  switch scale {
  case .fill:
    scaleValue = nil
  case .stretch:
    scaleValue = NSNumber(integerLiteral: 1)  // NSImageScaling.scaleAxesIndependently
  case .center:
    scaleValue = NSNumber(integerLiteral: 2)  // NSImageScaling.scaleNone
  case .fit:
    scaleValue = NSNumber(integerLiteral: 3)  // NSImageScaling.scaleProportionallyUpOrDown
  }

  // loop through all screens
  for screen in NSScreen.screens {
    let currentImageURL = ws.desktopImageURL(for: screen)
    let scalingKey = NSWorkspace.DesktopImageOptionKey.imageScaling
    var options = ws.desktopImageOptions(for: screen)
    if scaleValue == nil {
      options!.removeValue(forKey: scalingKey)
    } else {
      options![scalingKey] = scaleValue
    }
    try! ws.setDesktopImageURL(currentImageURL!, for: screen, options: options!)
  }
}

func imageScaling(for screen: NSScreen) -> ScaleOption? {
  let ws = NSWorkspace.shared
  guard let options = ws.desktopImageOptions(for: screen) else { return nil }
  let imageScalingValue = options[NSWorkspace.DesktopImageOptionKey.imageScaling] as? NSNumber
  var imageScaling: ScaleOption?
  if imageScalingValue == nil {
    imageScaling = .fill
  } else {
    switch imageScalingValue!.intValue {
    case 1:
      imageScaling = .stretch
    case 2:
      imageScaling = .center
    case 3:
      imageScaling = .fit
    default:
      imageScaling = nil
    }
  }
  return imageScaling
}
