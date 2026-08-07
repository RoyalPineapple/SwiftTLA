@TLAActor
actor Central {
    static var spec: TLASpec { ... }

    // Implementer provides side effects:
    func didBecomePoweredOn() { readyContinuation?.resume() }
    func didEnterScanning()  { central.scanForPeripherals(...) }
    func didLeaveScanning()  { central.stopScan() }
}

// Macro generates the state machine that calls the hooks:
//   func toPoweredOn() {
//       _state = _apply(.toPoweredOn)
//       if old != poweredOn { didBecomePoweredOn() }
//   }
//   func startScan() {
//       _state = _apply(.startScan)
//       didEnterScanning()
//   }
//
// CoreBluetooth delegate calls the generated methods:
//   func centralManagerDidUpdateState(...) {
//       Task { await self.updateState(...) }
//   }
//   func updateState(_ s: CBManagerState) { /* → toPoweredOn() etc */ }
