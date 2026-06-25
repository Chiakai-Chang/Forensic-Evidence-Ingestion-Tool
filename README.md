# Forensic Evidence Ingestion Tool (數位證據無損傳輸與歸檔工具)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-blue.svg)]()

本工具專為**現場數位鑑識人員返回駐地後保存與歸檔數位證據**所設計。旨在解決 Windows 系統下複製超長路徑檔案時容易卡死、傳輸緩慢，以及檔案與資料夾時間戳記（Metadata Timestamps）在複製過程中遭到修改等實務痛點，同時提供符合數位證據監管鏈（Chain of Custody）與同一性要求之雙重 SHA-256 雜湊對撞與驗證機制。

---

## 🌟 核心特色 (Key Features)

### 1. 超長路徑防禦 (Long Path Resolution)
Windows 檔案總管預設有 260 字元的路徑長度限制（`MAX_PATH`）。本工具在執行備份前，會**自動動態分配一個完全空閒的虛擬磁碟機代號**（優先從 `X:` 往回搜尋至 `D:`），並利用 `subst` 核心指令將超深的來源資料夾暫時掛載為該虛擬碟。此舉能硬生生將來源路徑長度縮短至僅 3 個字元（如 `X:\`），徹底根除路徑過長導致複製失敗或檔案損毀的風險。

### 2. 數位證據同一性確保 (Chain of Custody & Integrity)
- **先算後傳**：在移動任何實體檔案前，先在本地端以極速遍歷所有檔案並計算 **SHA-256 雜湊值**，記錄檔案大小與原始修改時間。
- **相對路徑設計**：雜湊值清單以**相對路徑**儲存（相對於虛擬碟根目錄），即使日後整批證據移動到不同的伺服器、外接碟或鑑識工作站，雜湊值比對亦不受絕對路徑變動的影響。
- **防斷線/Ctrl+C 遺失報告**：在檔案傳輸完成後，**立刻先存檔並同步**初始的 CSV 驗證清單。即使在後續耗時的「目的地二次驗算」過程中中途按下 `Ctrl + C` 關閉或因網路斷線，已產出的證據出生證明清單也早已安全寫入，不會遺失。

### 3. Metadata 原始時間戳記與屬性完美保留 (Metadata & Timestamps Preservation)
- **目錄與檔案無損**：Robocopy 備份核心預設使用 `/DCOPY:DAT /COPY:DAT` 參數，強制將所有子資料夾與檔案的原始修改時間、建立時間、存取時間以及系統屬性原封不動寫入目的地。
- **根目錄補正**：由於 Robocopy 無法將「來源根目錄本身」的時間戳記套用到「目的地根目錄本身」，腳本在複製結束後會自動透過 .NET 底層物件將來源根目錄的 `CreationTime`、`LastWriteTime`、`LastAccessTime` 與 `Attributes` 強制寫入目的地資料夾外殼，達到 100% 的外殼與內部時間戳記對齊。

### 4. 解決 UAC 管理員權限下「網路磁碟機隱形」問題
在 Windows 安全機制下（Split Token / UAC Isolation），「一般使用者」掛載的網路分享磁碟機（如 `Y:` 槽、`Z:` 槽）在「以系統管理員權限」執行的命令列中是完全隱形的。
本工具在啟動時會自動讀取註冊表 `HKCU:\Network` 紀錄，**在背景將使用者原有的網路磁碟連線動態克隆至管理員權限內**，使同仁在圖形選擇介面中能直接點選、寫入 NAS 或公用分享區，無需手動輸入複雜的 UNC IP 路徑。

### 5. 現代化 P/Invoke MessageBoxTimeout
本工具採用現代 **Win32 API (`MessageBoxTimeout`)** 進行防護型對話框調用，其視覺外觀與 Windows 10/11 系統風格完全一致，且能**避免使用高資安風險的傳統 Scripting 元件，安全繞過端點資安防護軟體（EDR）對指令碼彈窗的阻擋機制**。此視窗提供 10 秒自動倒數，時間到若無手動取消即自動同意並啟動目的地端二次雜湊驗算。

---

## 📂 專案檔案結構 (Project Structure)

* **[Evidence_Ingest_Tool.ps1](file:///D:/MyProject/Forensic-Evidence-Ingestion-Tool/Evidence_Ingest_Tool.ps1)**：PowerShell 核心鑑識歸檔與驗證模組。
* **[Run_Tool.bat](file:///D:/MyProject/Forensic-Evidence-Ingestion-Tool/Run_Tool.bat)**：全英文批次啟動檔，負責檢查並自動提權至系統管理員（UAC Bypass / Request Admin），並安全呼叫 PowerShell。
* **[.gitignore](file:///D:/MyProject/Forensic-Evidence-Ingestion-Tool/.gitignore)**：Git 忽略清單，已預先排除產出的臨時證據 CSV 報告與系統殘留檔。
* **[LICENSE](file:///D:/MyProject/Forensic-Evidence-Ingestion-Tool/LICENSE)**：MIT 授權條款。

---

## 🚀 快速上手 (Quick Start)

### 步驟 1：建立專案資料夾
在隨身碟、鑑識工作站或外接硬碟中建立一個資料夾，命名為：
`數位證據無損傳輸與歸檔工具`

### 步驟 2：放入工具檔案
將 [Evidence_Ingest_Tool.ps1](file:///D:/MyProject/Forensic-Evidence-Ingestion-Tool/Evidence_Ingest_Tool.ps1) 與 [Run_Tool.bat](file:///D:/MyProject/Forensic-Evidence-Ingestion-Tool/Run_Tool.bat) 放進上述資料夾中。

### 步驟 3：執行工具
1. 雙擊執行 **`Run_Tool.bat`**。
2. 系統會跳出 UAC 權限提升要求，請點擊「是」以系統管理員權限執行。
3. **選擇來源端**：在現代化檔案總管視窗中，點選您在現場扣案的原始數位證據資料夾（如 `E:\20260624_PC_證據`）。
4. **選擇目的地**：點選您要備份的遠端 NAS、公用分享區或儲存硬碟路徑（如 `Z:\★現場數位採證支援\`）。
5. **預覽確認**：在終端機視窗中核對來源路徑與目的地路徑是否正確無誤。
6. **開始備份**：按下 `Enter`（或輸入 Y）確認，程式將全自動完成虛擬碟掛載、來源雜湊計算、Robocopy 傳輸、虛擬碟拔除、產出報告並進行目的地驗算。

---

## 🛠️ 技術細節與 Robocopy 參數說明

* **`/E`**：複製所有子目錄（包含空目錄）。
* **`/DCOPY:DAT`**：複製目錄的資料 (Data)、屬性 (Attributes) 與時間戳記 (Timestamps)。
* **`/COPY:DAT`**：複製檔案的資料 (Data)、屬性 (Attributes) 與時間戳記 (Timestamps)。
* **`/R:2` 與 `/W:2`**：遇到鎖定檔案時最多重試 2 次，每次等待 2 秒（預設為重試 100 萬次，改為 2 次可避免因少數損毀檔導致整個傳輸卡死）。
* **`/NFL` / `/NDL` / `/NJH` / `/NJS`**：在傳輸十萬級別的小檔案時，隱藏單一檔案與目錄名稱，這能省去螢幕 I/O 的更新時間，使傳輸效率最高提升 30% 以上。

---

## ⚖️ 法律與鑑識聲明 (Disclaimer)
本工具主要設計用於數位證據同一性（Integrity）的保持與複製，產出的 CSV 報告包含每個檔案的 SHA-256 雜湊碼、檔案大小與修改時間。在進行正式法庭鑑定或扣案物封存時，請配合各單位標準作業程序（SOP）與監管鏈表單併案存檔，以確保數位證據之證據能力。

---
**開發人員**：[Chiakai Chang](mailto:contact.chiakai.chang@gmail.com)
**專案授權**：[MIT License](LICENSE)
