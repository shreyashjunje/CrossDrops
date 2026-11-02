//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import bonsoir_darwin
import file_picker_darwin
import package_info_plus
import wakelock_plus

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  SwiftBonsoirPlugin.register(with: registry.registrar(forPlugin: "SwiftBonsoirPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  WakelockPlusMacosPlugin.register(with: registry.registrar(forPlugin: "WakelockPlusMacosPlugin"))
}
