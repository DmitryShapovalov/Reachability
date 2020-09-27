//
//  Reachability.swift
//  Reachability
//
//  Created by Dmytro Shapovalov on 25.09.2020.
//

import Foundation
import SystemConfiguration

// MARK: - Local variable

fileprivate var notifierRunning = false
fileprivate var reachabilityRef: SCNetworkReachability?
fileprivate let reachabilitySerialQueue: DispatchQueue  = DispatchQueue(label: "com.dmytro.reachability", qos: .default, target: nil)
fileprivate var flags: SCNetworkReachabilityFlags? {
  didSet {
    guard flags != oldValue else { return }
    notifyReachabilityChanged()
  }
}
var isReachable: Bool {
  switch flags?.connection {
  case .unavailable?, nil: return false
  case .cellular?, .wifi?: return true
  }
}

// MARK: - Reachability struct

struct Reachability {
  var startNotifier: () -> Result<Void, ReachabilityError>
  var stopNotifier: () -> Void
}

extension Reachability {
  static var live: Self {
    return Self(
      startNotifier: {
        checkRunningState()
          .flatMap { createSCNetworkReachability() }
          .flatMap { pt in configureSCNetworkReachability(ref: pt).map { pt } }
          .flatMap { setReachabilityFlags(ref: $0) }
          .flatMap { updateRunningState() }
      },
      stopNotifier: {
        stopReachability()
      }
    )
  }
}

// MARK: - Reachability errors

public enum ReachabilityError: Error {
  case failedToCreateWithAddress(sockaddr, Int32)
  case unableToSetCallback(Int32)
  case unableToSetDispatchQueue(Int32)
  case unableToGetFlags(Int32)
  case alreadyRunning
  case unableToSetFlags
}

// MARK: - Notification name for reachability changes event

public extension Notification.Name {
  static let reachabilityChanged = Notification.Name("reachabilityChanged")
}

// MARK: - Reachability logic

fileprivate func checkRunningState() -> Result<Void, ReachabilityError> {
  if notifierRunning {
    return .failure(ReachabilityError.alreadyRunning)
  } else {
    return .success(())
  }
}

fileprivate func createSCNetworkReachability() -> Result<SCNetworkReachability, ReachabilityError> {
  var zeroAddress = sockaddr()
  zeroAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
  zeroAddress.sa_family = sa_family_t(AF_INET)
  guard let ref = SCNetworkReachabilityCreateWithAddress(nil, &zeroAddress) else {
    return .failure(ReachabilityError.failedToCreateWithAddress(zeroAddress, SCError()))
  }
  return .success(ref)
}

fileprivate func configureSCNetworkReachability(ref: SCNetworkReachability) -> Result<Void, ReachabilityError> {
  let callback: SCNetworkReachabilityCallBack = { (inputReachability, inputFlags, inputInfo) in
    flags = inputFlags
  }
  var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
  if !SCNetworkReachabilitySetCallback(ref, callback, &context) {
    stopReachability()
    return .failure(ReachabilityError.unableToSetCallback(SCError()))
  }
  if !SCNetworkReachabilitySetDispatchQueue(ref, reachabilitySerialQueue) {
    stopReachability()
    return .failure(ReachabilityError.unableToSetDispatchQueue(SCError()))
  }
  reachabilityRef = ref
  return .success(())
}

fileprivate func setReachabilityFlags(ref: SCNetworkReachability) -> Result<Void, ReachabilityError> {
  var result: Result<Void, ReachabilityError> = .failure(ReachabilityError.unableToSetFlags)
  reachabilitySerialQueue.sync {
    var inputFlags = SCNetworkReachabilityFlags()
    if !SCNetworkReachabilityGetFlags(ref, &inputFlags) {
      stopReachability()
      result = .failure(ReachabilityError.unableToGetFlags(SCError()))
    }
    flags = inputFlags
    result = .success(())
  }
  return result
}

fileprivate func updateRunningState() -> Result<Void, ReachabilityError> {
  notifierRunning = true
  return .success(())
}

fileprivate func stopReachability() {
  defer { notifierRunning = false }
  if let ref = reachabilityRef {
    SCNetworkReachabilitySetCallback(ref, nil, nil)
    SCNetworkReachabilitySetDispatchQueue(ref, nil)
  }
}

fileprivate func notifyReachabilityChanged() {
  let notify = { NotificationCenter.default.post(name: .reachabilityChanged, object: isReachable) }
  DispatchQueue.main.async(execute: notify)
}

extension SCNetworkReachabilityFlags {
  enum NetworkConnection {
    case unavailable
    case cellular
    case wifi
  }
  
  typealias Connection = NetworkConnection

  var connection: Connection {
    guard isReachableFlagSet else { return .unavailable }

    // If we're reachable, but not on an iOS device (i.e. simulator), we must be on WiFi
    #if targetEnvironment(simulator)
    return .wifi
    #else
    var connection = Connection.unavailable

    if !isConnectionRequiredFlagSet {
      connection = .wifi
    }

    if isConnectionOnTrafficOrDemandFlagSet {
      if !isInterventionRequiredFlagSet {
          connection = .wifi
      }
    }

    if isOnWWANFlagSet {
      connection = .cellular
    }

    return connection
    #endif
  }
  var isOnWWANFlagSet: Bool {
    #if os(iOS)
    return contains(.isWWAN)
    #else
    return false
    #endif
  }
  var isReachableFlagSet: Bool {
      return contains(.reachable)
  }
  var isConnectionRequiredFlagSet: Bool {
      return contains(.connectionRequired)
  }
  var isInterventionRequiredFlagSet: Bool {
      return contains(.interventionRequired)
  }
  var isConnectionOnTrafficFlagSet: Bool {
      return contains(.connectionOnTraffic)
  }
  var isConnectionOnDemandFlagSet: Bool {
      return contains(.connectionOnDemand)
  }
  var isConnectionOnTrafficOrDemandFlagSet: Bool {
      return !intersection([.connectionOnTraffic, .connectionOnDemand]).isEmpty
  }
  var isTransientConnectionFlagSet: Bool {
      return contains(.transientConnection)
  }
  var isLocalAddressFlagSet: Bool {
      return contains(.isLocalAddress)
  }
  var isDirectFlagSet: Bool {
      return contains(.isDirect)
  }
  var isConnectionRequiredAndTransientFlagSet: Bool {
      return intersection([.connectionRequired, .transientConnection]) == [.connectionRequired, .transientConnection]
  }
  var description: String {
    let W = isOnWWANFlagSet ? "W" : "-"
    let R = isReachableFlagSet ? "R" : "-"
    let c = isConnectionRequiredFlagSet ? "c" : "-"
    let t = isTransientConnectionFlagSet ? "t" : "-"
    let i = isInterventionRequiredFlagSet ? "i" : "-"
    let C = isConnectionOnTrafficFlagSet ? "C" : "-"
    let D = isConnectionOnDemandFlagSet ? "D" : "-"
    let l = isLocalAddressFlagSet ? "l" : "-"
    let d = isDirectFlagSet ? "d" : "-"
    return "\(W)\(R) \(c)\(t)\(i)\(C)\(D)\(l)\(d)"
  }
}
