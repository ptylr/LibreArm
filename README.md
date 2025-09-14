```
        __          .__
_______/  |_ ___.__.|  |_______
\____ \   __<   |  ||  |\_  __ \
|  |_> >  |  \___  ||  |_|  | \/
|   __/|__|  / ____||____/__|
|__|         \/

https://ptylr.com
https://www.linkedin.com/in/ptylr/
```

# LibreArm

LibreArm is an open‑source iOS app that connects directly to the **QardioArm** blood pressure monitor via Bluetooth Low Energy (BLE) and saves readings into **Apple Health**.  
This project exists because Qardio, Inc. shut down its backend services and app support, leaving the QardioArm hardware functional but unusable with the original app.

---

## ✨ Features

- Connects to QardioArm over BLE (no Qardio cloud or accounts required)
- Starts and stops a blood pressure measurement directly from the app
- Parses and displays **systolic**, **diastolic**, **MAP**, and **heart rate**
- Saves the **final measurement only** (debounced) into **Apple Health**
- Simple SwiftUI interface with live status and history through HealthKit
- 100% local: no accounts, no data leaves your device

---

## 📲 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ptylr/LibreArm.git
   cd LibreArm
   ```

2. Open the project in Xcode:
   ```bash
   open LibreArm.xcodeproj
   ```

3. Ensure you have:
   - Xcode 15+
   - iOS 16+ device (QardioArm does not work in the simulator)
   - An Apple ID signed into Xcode (free developer account works for local builds)

4. On first run you’ll be prompted for:
   - **Bluetooth access** (to connect to the cuff)
   - **Health access** (to save readings)

---

## 🔧 Development Notes

- **Language & UI**: Swift + SwiftUI
- **Bluetooth**: CoreBluetooth (service 0x1810, char 0x2A35 + vendor control UUID `583CB5B3-875D-40ED-9098-C39EB0C1983D`)
- **Health**: HealthKit (blood pressure and heart rate types)
- **App Icon**: Custom design included in `Assets.xcassets`

The app implements a debounce strategy so that **only the final reading** after a measurement is saved, preventing dozens of partial entries in Health.

---

## 🛡 Privacy

- LibreArm does **not** connect to the internet.  
- All readings stay on your device.  
- Data is saved into **Apple Health** if permission is granted.


---

## 🤝 Contributing

Pull requests are welcome! If you’d like to contribute improvements (UI, Bluetooth stability, documentation), please fork the repo and open a PR.

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

---

## Disclaimer
This document is provided for information purposes only. Paul Taylor may change the contents hereof without notice. This document is not warranted to be error-free, nor subject to any other warranties or conditions, whether expressed orally or implied in law, including implied warranties and conditions of merchantability or fitness for a particular purpose. Paul Taylor specifically disclaims any liability with respect to this document and no contractual obligations are formed either directly or indirectly by this document. The technologies, functionality, services, and processes described herein are subject to change without notice.

LibreArm is **not affiliated with or endorsed by Qardio, Inc.**  
QardioArm™ is a trademark of Qardio, Inc. This project is community‑driven to keep existing hardware usable.
