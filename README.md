# Lab 3：Digital Voice Recorder

Nexys A7 數位錄音機。使用板載 PDM 麥克風錄音，將資料存入 DDR2，並由音訊輸出播放。此專案目前支援正常播放、暫停、停止、2～8 倍快放，以及 1/2～1/8 倍慢放。

## 目前進度（2026-11-12）

- 錄音、DDR2 儲存與正常播放已完成。音訊時鐘為 3.125 MHz，錄音上限為 16 秒（`MAX_WORDS = 781_250` 個 64-bit 字）。
- 快放每個輸出週期消耗 `n` 個原始 PDM 位元，使用累加器維持輸出 `1` 的密度；慢放把每個原始位元重複 `n` 次。播放位置可跨越 64-bit 字邊界，播放中可切換倍率。
- 已加入播放前預讀，以及下一個 64-bit 字的緩衝。暫停會保留播放進度，停止後可從頭重播。
- 使用者已在實體板上做初步測試，回報目前看起來功能正常；各倍率的實測播放時間與長時間穩定性尚未記錄。
- 八位七段顯示器顯示狀態、原錄音位置秒數及播放倍率。LED9～LED15 新增七格 PDM 相對音量條；兩者都已通過獨立模擬，音量條板測仍待進行。
- Vivado 2026.1 已於 2026-11-12 完成較低音量門檻版本的綜合、布局繞線與 bitstream 產生。新版位於 `C:\DCLAB3_vivado\DCLAB3\DCLAB3.runs\impl_1\NEXYS_A7.bit`；舊音量門檻版備份為 `C:\Temp\NEXYS_A7_volume_led_old_thresholds.bit`，加入音量條前的備份為 `C:\Temp\NEXYS_A7_pre_volume_led.bit`。RTL 原始檔位於本資料夾，Vivado 專案位於 `C:\DCLAB3_vivado\DCLAB3\DCLAB3.xpr`。

## 板上操作

| 控制 | 功能 |
| --- | --- |
| `BTNC` | 重設系統 |
| `BTNU` | 開始錄音；錄音時再按一次，於目前 64-bit 字收滿後停止 |
| `BTNR` | 從頭播放；播放中按下為暫停，暫停中按下為繼續 |
| `BTND` | 停止錄音或播放 |
| `SW[3:0]` | 選擇播放速度；SW4～SW15 未用於速度控制 |

速度設定：`SW[2:0] + 1` 是倍率數字 `n`。`SW[3]=0` 時為 `n×`，`SW[3]=1` 時為 `1/n×`。兩種方向的 `n=1` 都是正常速度。

| `SW[3:0]` | 播放速度 |
| --- | --- |
| `0000` 或 `1000` | 1× |
| `0001`～`0111` | 2×～8× |
| `1001`～`1111` | 1/2×～1/8× |

`LED[8:5]` 顯示同步後的四位速度設定。`LED0` 為錄音中、`LED1` 為播放中、`LED2` 為暫停、`LED3` 為已有錄音、`LED4` 為錄音溢位或播放資料供應不足。`LED4` 會保持亮起，直到重設或開始新錄音。

### LED9～LED15 音量條

錄音時顯示麥克風 PDM 音量，播放時顯示送往音訊輸出的 PDM 音量；停止、暫停與播放前預讀時全暗。由 LED9 起往 LED15 依序增加亮燈數。音量計每 64 個 PDM 位元計算一次 1 的密度，扣除緩慢變動的直流偏移後取絕對值，再以約 42 ms 的時間尺度平滑。這是相對振幅指示，不是經過校準的聲壓分貝值。

平滑後的相對振幅達到 `0.5、0.75、1、1.5、2、3、4` 時，分別增加第 1～7 顆燈。音量計保留 16 位小數精度，直接比較平滑值，能顯示小於 1 的說話聲，也能在安靜後衰減到全暗。這些門檻是提高靈敏度後的試用值；若安靜時 LED9 常亮，應提高低段門檻；若正常說話仍不亮，應再降低門檻。門檻位於 `Pdm_Volume_Meter.sv` 的 `bar` 指派。

板測建議：

1. 重設或停止時確認 LED9～LED15 全暗，且 LED0～LED8 維持原本功能。
2. 開始錄音，在安靜環境、一般說話與較大聲說話時，確認亮燈數大致遞增；停止後全暗。
3. 播放同一段錄音，確認音量條隨聲音變化；按暫停後全暗，繼續播放後恢復，播放結束後全暗。
4. 切換 1×、快放及慢放，確認音量條仍會動態變化，且 LED4 不亮；音量條反映實際輸出的訊號，各速度的亮燈數不一定相同。
5. 若靜音時仍亮燈或一般說話無法顯示多格，依板上實測調整七個門檻。

在現有 Vivado 專案重新產生 bitstream：`vivado -mode batch -source build_volume_led.tcl`。腳本會加入新的音量計來源檔，並執行綜合、實作與 bitstream 產生。

## 七段顯示器（bonus）

八位數由左至右分成三位狀態、兩位原錄音位置秒數、三位速度。播放秒數按實際消耗的原始音訊位元前進，因此快放、慢放與暫停仍顯示錄音內容中的位置，而不是實際播放耗時。錄音最多顯示 `16` 秒；停止時顯示錄音總長。

| 顯示 | 意義 |
| --- | --- |
| `rEC05---` | 正在錄音，已錄 5 秒 |
| `PLY05F04` | 播放到原錄音第 5 秒，4× 快放 |
| `PAU05S04` | 暫停在原錄音第 5 秒，速度設定 1/4× |
| `PLY05n01` | 正常速度播放 |
| `StP12---` | 已停止，錄音總長 12 秒 |
| `Err12   ` | 錄音溢位或播放資料供應不足；空白位不點亮 |

`F02`～`F08` 代表 2×～8×，`S02`～`S08` 代表 1/2×～1/8×，`n01` 代表 1×。七段顯示器上的字母為近似字型。小數點 `DP` 保持關閉。

## 程式結構

| 檔案 | 用途 |
| --- | --- |
| `NEXYS_A7.sv` | 板上頂層：時鐘、按鍵、開關同步、LED、麥克風、音訊與 DDR2 接線 |
| `Pdm_Volume_Meter.sv` | 將 PDM 資料轉為七格相對音量條 |
| `Top.sv` | 錄音／播放狀態機、64-bit 資料緩衝、DDR2 請求、變速與原錄音秒數計算 |
| `ddr2_interface.sv` | Top 與 MIG 之間的 DDR2 交易及跨時鐘域同步 |
| `Debounce.sv` | 按鍵同步、去彈跳與按下脈波 |
| `Seven_Segment_Display.sv` | 八位七段顯示器的狀態排版、字型與掃描 |
| `Nexys-A7-100T-Master.xdc`、`mig.ucf` | 板上腳位與 DDR2 相關約束 |
| `sim/Top_speed_tb.sv` | 使用交易級 DDR2 模型驗證錄音及所有速度模式 |
| `sim/Seven_Segment_Display_tb.sv` | 驗證八位掃描、狀態、秒數及速度字型 |
| `sim/Pdm_Volume_Meter_tb.sv` | 驗證靜音、音量門檻、清空及直流偏移抑制 |
| `sim/Top_vivado_tb.sv` | 使用 Vivado IP 與 DDR2 模型的整合測試平台 |

## 已做的驗證

- `sim/Top_speed_tb.sv` 已通過 16 種 `SW[3:0]` 設定，並覆蓋跨字邊界、暫停／繼續、播放中切換速度，以及原錄音秒數。可在專案根目錄以 Icarus Verilog 重跑：

  ```powershell
  iverilog -g2012 -s Top_speed_tb -o "$env:TEMP\Top_speed_tb.vvp" Top.sv sim/Top_speed_tb.sv
  vvp "$env:TEMP\Top_speed_tb.vvp"
  ```

- `sim/Seven_Segment_Display_tb.sv` 已通過八位實體掃描輸出與各種狀態字型檢查：

  ```powershell
  iverilog -g2012 -s Seven_Segment_Display_tb -o "$env:TEMP\Seven_Segment_Display_tb.vvp" Seven_Segment_Display.sv sim/Seven_Segment_Display_tb.sv
  vvp "$env:TEMP\Seven_Segment_Display_tb.vvp"
  ```

- `sim/Pdm_Volume_Meter_tb.sv` 已通過靜音、小於 1 的振幅門檻、中等／較大振幅、安靜後衰減、停止時清空和固定直流偏移抑制：

  ```powershell
  iverilog -g2012 -s Pdm_Volume_Meter_tb -o "$env:TEMP\Pdm_Volume_Meter_tb.vvp" Pdm_Volume_Meter.sv sim/Pdm_Volume_Meter_tb.sv
  vvp "$env:TEMP\Pdm_Volume_Meter_tb.vvp"
  ```

- 2026-11-12 較低門檻版本的 routed timing report 顯示 WNS `+0.619 ns`、WHS `+0.019 ns`、TNS/THS 均為 `0`；bitstream 前 DRC 為 `0 errors`。時鐘方法學警告仍如後述，正餘裕只代表目前約束下的結果。

- 2026-11-09 的新版 routed timing report 顯示 WNS `+0.682 ns`、WHS `+0.019 ns`、TNS/THS 均為 `0`；bitstream 前 DRC 為 `0 errors`。時鐘方法學警告仍如後述，正餘裕只代表目前約束下的結果。

- 2026-11-04 的 routed timing report 顯示 WNS `+0.589 ns`、WHS `+0.019 ns`、TNS/THS 均為 `0`；路由完成，bitstream 前的 DRC 為 `0 errors`。
- 完整 MIG＋DDR2 行為模擬在記憶體模型初始化階段出現 `Load Mode Failure: All banks must be Precharged`，尚未進入音訊測試。交易級測試已通過、初步板測看起來正常，但此整合模擬尚未通過。

## 已知警告與後續工作

1. **時鐘約束需整理。** `Nexys-A7-100T-Master.xdc` 第 9 行與 Clock Wizard 產生的 XDC 對同一個 100 MHz 輸入建立兩個 primary clocks。Methodology report 有 44 筆 `TIMING-6` critical warnings 及 21 筆 `TIMING-56`。應保留一個正確的時鐘定義後重新檢查時序；目前的正餘裕只代表現有約束下的結果。
2. **非同步重設網路需檢查。** `LUTAR-1` 指出 LUT 驅動非同步 reset，可能有毛刺風險；若板上偶發自行重置，優先檢查 `Top.sv` 的 `locked && !rst` 及相關重設路徑。
3. **DDR2 時鐘警告需留意。** `REQP-1709` 指出 MIG PLL 輸出使用不同類型的 clock buffer，可能影響相位對齊。以板上 DDR2 校準、錄音及讀回穩定性作為後續驗證重點；不要直接修改產生的 IP 檔案。
4. 新版 bitstream 已包含七段顯示器和音量條，尚需燒錄到板上驗證字型順序、亮度、錄放秒數及音量門檻。`PLIO-3` 主要來自未使用外設的部分腳位約束；`CFGBVS-1` 表示尚未指定配置電壓屬性。
5. 記錄完整的板測結果：同一段錄音的 1× 時間為 `T` 時，確認各檔快放約為 `T/n`、慢放約為 `nT`，並確認長時間播放時 `LED4` 不亮。
