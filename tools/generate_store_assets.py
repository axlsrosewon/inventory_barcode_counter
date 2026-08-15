from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "store_assets"
RAW = STORE / "screenshots" / "raw"


def font(size, bold=False):
    names = [
        "C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf",
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
    ]
    for name in names:
        path = Path(name)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def text(draw, xy, value, size=32, fill="#17231f", bold=False, anchor=None):
    draw.text(xy, value, font=font(size, bold), fill=fill, anchor=anchor)


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def barcode(draw, x, y, w, h, fill="#17231f"):
    widths = [5, 2, 3, 8, 2, 5, 3, 2, 7, 2, 3, 5, 2, 8, 3, 2, 5]
    cursor = x
    total = sum(widths)
    scale = w / total
    for i, value in enumerate(widths):
        bar_w = max(2, int(value * scale))
        if i % 2 == 0:
            draw.rectangle((cursor, y, cursor + bar_w, y + h), fill=fill)
        cursor += bar_w


def make_icon(size):
    img = Image.new("RGB", (size, size), "#0f766e")
    d = ImageDraw.Draw(img)
    pad = int(size * 0.14)
    rounded(d, (pad, pad, size - pad, size - pad), int(size * 0.08), "#f8fbfa")
    barcode(d, int(size * 0.24), int(size * 0.34), int(size * 0.52), int(size * 0.25), "#0f766e")
    rounded(d, (int(size * 0.29), int(size * 0.64), int(size * 0.71), int(size * 0.76)), int(size * 0.03), "#0f766e")
    text(d, (size // 2, int(size * 0.70)), "+1", int(size * 0.10), "#ffffff", True, "mm")
    return img


def top_bar(draw, mode):
    text(draw, (64, 72), "재고 실사 바코드 카운터", 40, "#17231f", True)
    labels = [("스캔", mode == "scan"), ("목록", mode == "list"), ("CSV", mode == "csv")]
    rounded(draw, (48, 150, 1032, 270), 18, "#ffffff", "#d5dfdc", 2)
    for i, (label, active) in enumerate(labels):
        x1 = 90 + i * 300
        rounded(draw, (x1, 184, x1 + 240, 238), 14, "#0f766e" if active else "#ffffff", "#0f766e", 2)
        text(draw, (x1 + 120, 211), label, 25, "#ffffff" if active else "#0f766e", True, "mm")


def phone_frame(title, mode="scan"):
    img = Image.new("RGB", (1080, 1920), "#f6f7f2")
    d = ImageDraw.Draw(img)
    top_bar(d, mode)
    text(d, (64, 310), title, 32, "#64748b", True)

    if mode == "scan":
        rounded(d, (80, 390, 1000, 1240), 28, "#10201d")
        rounded(d, (250, 560, 830, 1030), 24, "#10201d", "#ffffff", 8)
        barcode(d, 345, 735, 390, 150, "#ffffff")
        rounded(d, (80, 1300, 520, 1430), 18, "#ffffff", "#d5dfdc", 2)
        rounded(d, (560, 1300, 1000, 1430), 18, "#ffffff", "#d5dfdc", 2)
        text(d, (120, 1328), "항목", 26, "#64748b")
        text(d, (120, 1372), "24", 46, "#17231f", True)
        text(d, (600, 1328), "총 수량", 26, "#64748b")
        text(d, (600, 1372), "67", 46, "#17231f", True)
        rounded(d, (80, 1500, 1000, 1635), 20, "#ffffff", "#d5dfdc", 2)
        text(d, (120, 1530), "최근 스캔", 28, "#64748b")
        text(d, (120, 1580), "8801234567890", 32, "#17231f", True)
    elif mode == "list":
        rows = [
            ("8801234567890", "Sample Item", "3"),
            ("4901234567894", "부품 박스 A", "12"),
            ("978020137962", "작업 노트", "5"),
            ("QR-WORKSHOP-01", "공방 소모품", "47"),
        ]
        for i, (code, name, qty) in enumerate(rows):
            y = 410 + i * 260
            rounded(d, (70, y, 1010, y + 210), 18, "#ffffff", "#d5dfdc", 2)
            text(d, (110, y + 50), code, 32, "#17231f", True)
            text(d, (110, y + 100), name, 26, "#64748b")
            rounded(d, (710, y + 62, 790, y + 142), 40, "#eef6f4", "#0f766e", 2)
            text(d, (750, y + 102), "-", 34, "#0f766e", True, "mm")
            text(d, (850, y + 102), qty, 42, "#17231f", True, "mm")
            rounded(d, (910, y + 62, 990, y + 142), 40, "#0f766e")
            text(d, (950, y + 102), "+", 34, "#ffffff", True, "mm")
    else:
        rounded(d, (80, 410, 1000, 600), 20, "#ffffff", "#d5dfdc", 2)
        text(d, (120, 470), "내보낼 행 수", 30, "#64748b")
        text(d, (120, 545), "24", 62, "#17231f", True)
        rounded(d, (80, 660, 1000, 1220), 20, "#ffffff", "#d5dfdc", 2)
        csv_lines = [
            "code,name,quantity,...",
            "8801234567890,Sample Item,3,...",
            "4901234567894,부품 박스 A,12,...",
            "QR-WORKSHOP-01,공방 소모품,47,...",
        ]
        for i, line in enumerate(csv_lines):
            text(d, (120, 730 + i * 88), line, 26, "#17231f" if i else "#0f766e", i == 0)
        rounded(d, (160, 1370, 920, 1470), 22, "#0f766e")
        text(d, (540, 1420), "CSV 저장/공유", 34, "#ffffff", True, "mm")

    rounded(d, (300, 1815, 780, 1870), 20, "#17231f")
    return img


def make_feature():
    img = Image.new("RGB", (1024, 500), "#f6f7f2")
    d = ImageDraw.Draw(img)
    text(d, (54, 72), "재고 실사 바코드 카운터", 46, "#0f766e", True)
    text(d, (56, 138), "바코드 스캔으로 수량을 세고 CSV로 공유", 30, "#17231f", True)
    text(d, (56, 190), "회원가입 없이 시작. 같은 코드는 자동 +1.", 25, "#64748b")
    rounded(d, (56, 292, 245, 365), 18, "#0f766e")
    text(d, (150, 328), "Scan", 28, "#ffffff", True, "mm")
    rounded(d, (270, 292, 520, 365), 18, "#ffffff", "#0f766e", 2)
    text(d, (395, 328), "CSV Export", 28, "#0f766e", True, "mm")
    rounded(d, (56, 405, 595, 445), 10, "#ffffff", "#d5dfdc", 1)
    text(d, (76, 425), "Local DB / No login / Free CSV", 23, "#17231f", False, "lm")
    phone = phone_frame("스캔 즉시 수량 합산", "list").resize((250, 444))
    img.paste(phone, (710, 28))
    return img


def write_listing():
    listing = """{
  "title": "재고 실사 바코드 카운터",
  "short_description": "바코드로 수량을 세고 CSV로 공유하는 실사 카운터",
  "full_description": "재고 실사 바코드 카운터는 소규모 매장, 창고, 공방에서 빠르게 재고 수량을 확인하기 위한 로컬 우선 스캔 도구입니다. 회원가입이나 복잡한 창고 설정 없이 새 실사를 시작하고, 바코드나 QR 코드를 스캔하면 같은 코드는 중복 행으로 쌓이지 않고 수량이 자동으로 증가합니다.\\n\\n주요 기능\\n- 날짜 기준 실사 세션 생성\\n- 카메라 바코드/QR 스캔\\n- 같은 코드 재스캔 시 수량 자동 +1\\n- 바코드 수동 입력\\n- 상품명 또는 메모 입력\\n- + / - 버튼과 직접 입력으로 수량 수정\\n- 최근 스캔 취소\\n- code, name, quantity, first_scanned_at, last_scanned_at CSV 내보내기\\n- Android 공유 시트로 CSV 공유\\n- 서버 없이 기기 내부에 로컬 저장\\n\\n이 앱은 판매, 구매, 입출고, 클라우드 동기화 기능을 제공하는 재고관리 시스템이 아닙니다. 실사 현장에서 빠르게 세고 CSV 파일로 넘기기 위한 단순한 스캔 카운터입니다.",
  "release_notes": "Initial release of Inventory Barcode Counter."
}
"""
    (STORE / "store_listing_ko.json").write_text(listing, encoding="utf-8")


def main():
    STORE.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)

    make_icon(512).save(STORE / "play_icon_512.png")
    make_feature().save(STORE / "feature_graphic_1024x500.png")
    phone_frame("바코드 스캔", "scan").save(RAW / "01_scan.png")
    phone_frame("중복 스캔 수량 합산", "list").save(RAW / "02_list.png")
    phone_frame("항목 검색과 수량 수정", "list").save(RAW / "03_edit.png")
    phone_frame("CSV 저장 및 공유", "csv").save(RAW / "04_export.png")
    write_listing()

    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in densities.items():
        target = ROOT / "android" / "app" / "src" / "main" / "res" / folder
        target.mkdir(parents=True, exist_ok=True)
        make_icon(size).save(target / "ic_launcher.png")


if __name__ == "__main__":
    main()
