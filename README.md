# Aseprite Batch Export

เครื่องมือ GUI บน Windows สำหรับ export sprite sheet จากไฟล์ `.aseprite` แบบ batch — เลือก layer และ tag ที่ต้องการ แล้วมันจะไล่ export **ทุกคู่ layer × tag** ให้ในคลิกเดียว

เหมาะกับงานที่ตัวละครหนึ่งตัวมีหลายสี (เก็บเป็น layer) และหลายท่าทาง (เก็บเป็น tag) เช่น 3 สี × 4 ท่า = 12 ไฟล์ ที่ปกติต้องนั่ง export ทีละอัน

---

## ต้องมีอะไรบ้าง

- **Windows** (ทดสอบบน Windows 11) — ใช้ PowerShell 5.1 กับ .NET Framework ที่ติดมากับเครื่องอยู่แล้ว ไม่ต้องลงอะไรเพิ่ม
- **Aseprite** ฉบับที่มี CLI (ตัวที่ซื้อจาก Steam / itch.io / เว็บทางการ ใช้ได้หมด) — ต้องรู้ path ของ `Aseprite.exe`

> path ที่พบบ่อย
> `C:\Program Files\Aseprite\Aseprite.exe`
> `C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe`
>
> ถ้าลง Steam ไว้คนละไดรฟ์ ให้ดูใน `SteamLibrary\steamapps\common\Aseprite\`

---

## วิธีใช้

1. ดับเบิลคลิก **`Aseprite Batch Export.bat`**
2. ช่อง **aseprite.exe** → กด `Browse...` ชี้ไปที่ `Aseprite.exe`
3. ช่อง **.aseprite file** → กด `Browse...` เลือกไฟล์งาน
   โปรแกรมจะ **สแกนไฟล์อัตโนมัติ** แล้วเอา layer/tag ที่มีอยู่จริงมาขึ้นเป็นรายการให้ติ๊ก
   (ถ้าแก้ path ด้วยการพิมพ์เอง ให้กดปุ่ม **Scan ไฟล์** เอง)
4. ติ๊กเลือก **Layers** และ **Tags** ที่ต้องการ — ดูชื่อไฟล์ที่จะได้ในแท็บ **พรีวิวชื่อไฟล์** ด้านล่าง
5. ตั้ง **Output prefix** กับ **Output folder** (ถ้าเว้นว่างไว้ จะใช้ชื่อ/โฟลเดอร์ของไฟล์ `.aseprite` เป็นค่าตั้งต้น)
6. กด **Export** — ดูความคืบหน้าได้ในแท็บ **Log**

ค่าที่ตั้งไว้จะถูกบันทึกตอนกด Export และโหลดกลับให้อัตโนมัติในครั้งถัดไป (รวมถึงติ๊ก layer/tag เดิมให้ด้วย)

---

## ชื่อไฟล์ผลลัพธ์

```
<prefix>_<layer>_<tag>.png
```

ช่องว่างในชื่อ tag จะถูกแทนด้วย `_` เช่น prefix `hero`, layer `blue`, tag `Attack Down`:

```
hero_blue_Attack_Down.png
```

แท็บ **พรีวิวชื่อไฟล์** จะแสดงรายชื่อทั้งหมดแบบสด ๆ พร้อมคำเตือน 2 แบบ:

| คำเตือน | หมายถึง |
| --- | --- |
| `<< มีไฟล์เดิม จะถูกเขียนทับ` | ในโฟลเดอร์ปลายทางมีไฟล์ชื่อนี้อยู่แล้ว |
| `<< ชื่อซ้ำ! จะทับกันเอง` | มีสองคู่ layer/tag ที่ให้ชื่อไฟล์เดียวกัน เช่น tag `Attack Down` กับ `Attack_Down` |

---

## ปุ่มและตัวเลือก

| ส่วน | ทำอะไร |
| --- | --- |
| **Scan ไฟล์** | ดึงรายชื่อ layer และ tag จากไฟล์ `.aseprite` มาขึ้นลิสต์ (ติ๊กที่เลือกไว้เดิมจะถูกติ๊กคืนให้) |
| **เลือกทั้งหมด / ล้าง** | ติ๊ก/ยกเลิกทั้งลิสต์ |
| **+ เพิ่มเอง** | พิมพ์ชื่อ layer/tag เพิ่มเข้าลิสต์เอง เผื่อกรณีสแกนไม่ได้ผล |
| **Sheet type** | รูปแบบการจัดเรียงเฟรม: `horizontal`, `vertical`, `rows`, `columns`, `packed` |
| **Ignore empty frames** | ข้ามเฟรมที่ว่างเปล่า (ส่ง `--ignore-empty` ให้ Aseprite) |
| **Output prefix** | คำนำหน้าชื่อไฟล์ — เว้นว่าง = ใช้ชื่อไฟล์ `.aseprite` |
| **Open Output Folder** | เปิดโฟลเดอร์ปลายทางใน Explorer |

---

## เบื้องหลังทำงานยังไง

ทั้งหมดเรียก Aseprite CLI ในโหมด batch (`-b`) ไม่เปิดหน้าต่างโปรแกรม

**ตอนสแกน**

```
Aseprite.exe -b --list-layers <file.aseprite>
Aseprite.exe -b --list-tags   <file.aseprite>
```

**ตอน export** (ยิงหนึ่งครั้งต่อหนึ่งคู่ layer × tag)

```
Aseprite.exe -b --layer <layer> --frame-tag <tag> <file.aseprite> [--ignore-empty] --sheet-type <type> --sheet <output.png>
```

ก่อน export แต่ละไฟล์ โปรแกรมจะลบไฟล์ปลายทางเดิมทิ้งก่อน เพื่อให้สถานะ `OK` ในหน้า Log แปลว่า "สร้างไฟล์สำเร็จจริงในรอบนี้" ไม่ใช่แค่เจอไฟล์เก่าค้างอยู่

---

## ไฟล์ในโปรเจค

| ไฟล์ | คืออะไร |
| --- | --- |
| `Aseprite Batch Export.bat` | ตัวเปิดโปรแกรม (รัน PowerShell แบบซ่อนหน้าต่าง) |
| `AsepriteExportGUI.ps1` | ตัวโปรแกรมทั้งหมด (WinForms) |
| `aseprite_export_settings.json` | ค่าที่บันทึกไว้ครั้งล่าสุด — สร้างอัตโนมัติตอนกด Export ครั้งแรก ลบทิ้งได้ถ้าอยากรีเซ็ต |

---

## แก้ปัญหา

**กด Scan แล้วลิสต์ว่างเปล่า**
ดูข้อความจาก Aseprite ในแท็บ Log ประกอบ — อาจเป็นเวอร์ชันเก่าที่ยังไม่มี `--list-layers` / `--list-tags` หรือไฟล์นั้นไม่มี tag เลย ระหว่างนี้ใช้ปุ่ม **+ เพิ่มเอง** พิมพ์ชื่อเองไปก่อนได้

**Log ขึ้น `WARNING: ไม่พบไฟล์ผลลัพธ์`**
Aseprite รันจบแต่ไม่ได้เขียนไฟล์ออกมา สาเหตุที่พบบ่อยคือชื่อ layer/tag ไม่ตรงเป๊ะ (ตัวพิมพ์เล็ก-ใหญ่ต่างกัน) หรือ tag นั้นไม่มีเฟรมใน layer นั้นจริง ๆ — ดู exit code กับข้อความที่ต่อท้ายในบรรทัดเดียวกัน

**เปิดแล้วไม่มีอะไรขึ้น**
ลองรัน `AsepriteExportGUI.ps1` จากหน้าต่าง PowerShell ตรง ๆ เพื่อดู error:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ".\AsepriteExportGUI.ps1"
```

**แก้โค้ดแล้วภาษาไทยกลายเป็นตัวประหลาด**
`AsepriteExportGUI.ps1` ต้องบันทึกเป็น **UTF-8 with BOM** เท่านั้น — PowerShell 5.1 อ่านไฟล์ UTF-8 ที่ไม่มี BOM เป็น ANSI ทำให้ข้อความไทยเพี้ยนทั้งไฟล์

---

## ข้อจำกัดที่รู้อยู่

- ทำได้ทีละไฟล์ `.aseprite` (batch ในที่นี้หมายถึงหลาย layer × tag ไม่ใช่หลายไฟล์)
- ไฟล์ settings เก็บรายการที่เลือกเป็นข้อความคั่นจุลภาค ถ้าชื่อ layer/tag มีเครื่องหมาย `,` อยู่ในตัว การติ๊กคืนอัตโนมัติจะไม่ตรง (ตัว export เองไม่มีปัญหา)
- ระหว่าง export หน้าต่างจะค้างเล็กน้อยเพราะรัน Aseprite แบบรอทีละคู่
