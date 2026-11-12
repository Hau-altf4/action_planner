"""Xuất báo cáo đồ án từ main.tex thành PDF để nộp và xem ngoại tuyến."""

from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = Path(__file__).resolve().parents[1]
TEX_FILE = ROOT / "report" / "overleaf" / "main.tex"
OUTPUT_FILE = ROOT / "output" / "pdf" / "bao_cao_do_an_action_planner.pdf"


def register_fonts() -> tuple[str, str, str, str]:
    fonts = Path(r"C:\Windows\Fonts")
    names = {
        "ReportSerif": fonts / "times.ttf",
        "ReportSerif-Bold": fonts / "timesbd.ttf",
        "ReportSerif-Italic": fonts / "timesi.ttf",
        "ReportMono": fonts / "consola.ttf",
    }
    for name, path in names.items():
        pdfmetrics.registerFont(TTFont(name, str(path)))
    pdfmetrics.registerFontFamily(
        "ReportSerif",
        normal="ReportSerif",
        bold="ReportSerif-Bold",
        italic="ReportSerif-Italic",
    )
    return tuple(names)  # type: ignore[return-value]


SERIF, SERIF_BOLD, SERIF_ITALIC, MONO = register_fonts()
BLUE = colors.HexColor("#173F7A")
RED = colors.HexColor("#A61B1B")
LIGHT_BLUE = colors.HexColor("#EEF4FB")
LIGHT_GRAY = colors.HexColor("#F4F5F7")


class ReportDocument(BaseDocTemplate):
    def __init__(self, filename: str):
        super().__init__(
            filename,
            pagesize=A4,
            leftMargin=3.2 * cm,
            rightMargin=2 * cm,
            topMargin=2.3 * cm,
            bottomMargin=2.2 * cm,
            title="Hệ thống thông tin chủ động cho hành động cá nhân",
            author="Võ Trọng Tài và Nguyễn Cao Hậu",
        )
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="normal")
        self.addPageTemplates(PageTemplate(id="report", frames=frame, onPage=self._draw_page))

    def _draw_page(self, canvas, doc):
        canvas.saveState()
        if doc.page > 1:
            canvas.setStrokeColor(colors.HexColor("#B6C2D2"))
            canvas.setLineWidth(0.4)
            canvas.line(self.leftMargin, A4[1] - 1.55 * cm, A4[0] - self.rightMargin, A4[1] - 1.55 * cm)
            canvas.setFont(SERIF, 8.5)
            canvas.setFillColor(colors.HexColor("#3F4A5A"))
            canvas.drawString(self.leftMargin, A4[1] - 1.25 * cm, "HỆ THỐNG THÔNG TIN CHỦ ĐỘNG CHO HÀNH ĐỘNG CÁ NHÂN")
            canvas.drawCentredString(A4[0] / 2, 1.15 * cm, str(doc.page - 1))
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            style = flowable.style.name
            if style in {"Chapter", "Section", "Subsection"}:
                level = {"Chapter": 0, "Section": 1, "Subsection": 2}[style]
                text = flowable.getPlainText()
                key = f"heading-{self.seq.nextf('heading')}"
                self.canv.bookmarkPage(key)
                self.canv.addOutlineEntry(text, key, level=level, closed=False)
                self.notify("TOCEntry", (level, text, self.page - 1, key))


styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="BodyVN", fontName=SERIF, fontSize=11.2, leading=17, alignment=TA_JUSTIFY, spaceAfter=7))
styles.add(ParagraphStyle(name="Chapter", fontName=SERIF_BOLD, fontSize=18, leading=23, alignment=TA_CENTER, textColor=BLUE, spaceBefore=8, spaceAfter=18, keepWithNext=True))
styles.add(ParagraphStyle(name="Section", fontName=SERIF_BOLD, fontSize=14, leading=18, textColor=BLUE, spaceBefore=13, spaceAfter=7, keepWithNext=True))
styles.add(ParagraphStyle(name="Subsection", fontName=SERIF_BOLD, fontSize=12, leading=16, textColor=colors.HexColor("#243850"), spaceBefore=9, spaceAfter=5, keepWithNext=True))
styles.add(ParagraphStyle(name="BulletVN", parent=styles["BodyVN"], leftIndent=14, firstLineIndent=-9, bulletIndent=3, spaceAfter=4))
styles.add(ParagraphStyle(name="CaptionVN", fontName=SERIF_ITALIC, fontSize=9.5, leading=13, alignment=TA_CENTER, textColor=colors.HexColor("#4B5563"), spaceBefore=4, spaceAfter=9))
styles.add(ParagraphStyle(name="CodeVN", fontName=MONO, fontSize=7.8, leading=10, leftIndent=7, rightIndent=7, borderColor=colors.HexColor("#D7DCE2"), borderWidth=0.5, borderPadding=7, backColor=LIGHT_GRAY, spaceBefore=5, spaceAfter=8))


def extract_braced(line: str, command: str) -> str:
    marker = f"\\{command}{{"
    start = line.find(marker)
    if start < 0:
        return ""
    start += len(marker)
    depth = 1
    for pos in range(start, len(line)):
        if line[pos] == "{":
            depth += 1
        elif line[pos] == "}":
            depth -= 1
            if depth == 0:
                return line[start:pos]
    return line[start:]


def clean_tex(value: str) -> str:
    value = value.replace("~", " ")
    value = re.sub(r"\\(textbf|emph|textit)\{([^{}]*)\}", lambda m: f"<b>{m.group(2)}</b>" if m.group(1) == "textbf" else f"<i>{m.group(2)}</i>", value)
    value = re.sub(r"\\texttt\{([^{}]*)\}", lambda m: f"<font name='{MONO}'>{html.escape(m.group(1))}</font>", value)
    value = re.sub(r"\\url\{([^{}]*)\}", lambda m: html.escape(m.group(1)), value)
    value = re.sub(r"\\href\{([^{}]*)\}\{([^{}]*)\}", lambda m: html.escape(m.group(2)), value)
    value = re.sub(r"\\(label|ref|cite)\{[^{}]*\}", "", value)
    value = value.replace(r"\%", "%").replace(r"\&", "&amp;").replace(r"\_", "_").replace(r"\#", "#")
    value = re.sub(r"\\[a-zA-Z*]+(?:\[[^\]]*\])?", "", value)
    value = value.replace("{", "").replace("}", "")
    value = re.sub(r"\s+", " ", value).strip()
    return value


def cover_story() -> list:
    return [
        Spacer(1, 0.2 * cm),
        Paragraph("<b>TRƯỜNG ĐẠI HỌC KIẾN TRÚC ĐÀ NẴNG</b>", ParagraphStyle("CoverSchool", fontName=SERIF_BOLD, fontSize=14, leading=19, alignment=TA_CENTER, textColor=BLUE)),
        Paragraph("<b>KHOA CÔNG NGHỆ THÔNG TIN</b>", ParagraphStyle("CoverFaculty", fontName=SERIF_BOLD, fontSize=13, leading=18, alignment=TA_CENTER)),
        Spacer(1, 1.4 * cm),
        Table([[""]], colWidths=[3.2 * cm], rowHeights=[0.12 * cm], style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), RED), ("BOX", (0, 0), (-1, -1), 0, RED)])),
        Spacer(1, 1.4 * cm),
        Paragraph("<b>BÁO CÁO ĐỒ ÁN CHUYÊN SÂU</b>", ParagraphStyle("CoverType", fontName=SERIF_BOLD, fontSize=16, leading=22, alignment=TA_CENTER, textColor=RED)),
        Spacer(1, 0.7 * cm),
        Paragraph("<b>XÂY DỰNG HỆ THỐNG THÔNG TIN CHỦ ĐỘNG<br/>CHO HÀNH ĐỘNG CÁ NHÂN</b>", ParagraphStyle("CoverTitle", fontName=SERIF_BOLD, fontSize=21, leading=29, alignment=TA_CENTER, textColor=BLUE)),
        Spacer(1, 1.7 * cm),
        Table(
            [
                [Paragraph("<b>Sinh viên thực hiện</b>", styles["BodyVN"]), Paragraph("Võ Trọng Tài - 2351220084", styles["BodyVN"])],
                ["", Paragraph("Nguyễn Cao Hậu - <i>Bổ sung MSSV</i>", styles["BodyVN"])],
                [Paragraph("<b>Giảng viên hướng dẫn</b>", styles["BodyVN"]), Paragraph("ThS. Trần Thanh", styles["BodyVN"])],
            ],
            colWidths=[5.3 * cm, 8.5 * cm],
            style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]),
        ),
        Spacer(1, 3.4 * cm),
        Paragraph("<b>Đà Nẵng, 2026</b>", ParagraphStyle("CoverDate", fontName=SERIF_BOLD, fontSize=12, alignment=TA_CENTER)),
        PageBreak(),
    ]


def table_from_lines(lines: list[str]):
    joined = " ".join(lines)
    joined = re.sub(r"\\(toprule|midrule|bottomrule|hline)", " ", joined)
    rows = []
    for raw_row in re.split(r"\\\\", joined):
        raw_row = re.sub(r"\\endhead|\\endfirsthead", "", raw_row)
        cells = [clean_tex(cell) for cell in raw_row.split("&")]
        cells = [cell for cell in cells if cell]
        if len(cells) >= 2:
            rows.append([Paragraph(cell, ParagraphStyle("TableCell", fontName=SERIF, fontSize=8.4, leading=11)) for cell in cells])
    if not rows:
        return None
    columns = max(len(row) for row in rows)
    for row in rows:
        row.extend([""] * (columns - len(row)))
    widths = [14.8 * cm / columns] * columns
    table = Table(rows, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), BLUE),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), SERIF_BOLD),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#AEB8C5")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_BLUE]),
    ]))
    return table


def body_story(tex: str) -> list:
    source = tex.split(r"\begin{document}", 1)[-1].split(r"\end{document}", 1)[0]
    first_chapter = source.find(r"\chapter*{LỜI CAM ĐOAN}")
    if first_chapter >= 0:
        source = source[first_chapter:]
    lines = source.splitlines()
    story: list = []
    paragraph: list[str] = []
    started = False
    in_code = False
    code_lines: list[str] = []
    in_table = False
    table_lines: list[str] = []
    in_tikz = False

    def flush_paragraph():
        if paragraph:
            value = clean_tex(" ".join(paragraph))
            if len(value) > 2:
                story.append(Paragraph(value, styles["BodyVN"]))
            paragraph.clear()

    for line in lines:
        stripped = line.strip()
        if r"\begin{lstlisting}" in stripped:
            flush_paragraph(); in_code = True; code_lines = []; continue
        if in_code:
            if r"\end{lstlisting}" in stripped:
                story.append(Preformatted("\n".join(code_lines), styles["CodeVN"])); in_code = False
            else:
                code_lines.append(line)
            continue
        if re.search(r"\\begin\{(?:longtable|tabularx|tabular)\}", stripped):
            flush_paragraph(); in_table = True; table_lines = []; continue
        if in_table:
            if re.search(r"\\end\{(?:longtable|tabularx|tabular)\}", stripped):
                table = table_from_lines(table_lines)
                if table:
                    story.extend([table, Spacer(1, 0.22 * cm)])
                in_table = False
            else:
                table_lines.append(stripped)
            continue
        if r"\begin{tikzpicture}" in stripped:
            flush_paragraph(); in_tikz = True; continue
        if in_tikz:
            if r"\end{tikzpicture}" in stripped:
                in_tikz = False
                story.append(Table([[Paragraph("Sơ đồ được trình bày chi tiết trong mã nguồn Overleaf.", styles["CaptionVN"])]], colWidths=[14.8 * cm], style=TableStyle([("BOX", (0, 0), (-1, -1), 0.7, BLUE), ("BACKGROUND", (0, 0), (-1, -1), LIGHT_BLUE), ("TOPPADDING", (0, 0), (-1, -1), 10), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)])))
            continue
        if stripped.startswith(r"\chapter"):
            flush_paragraph(); started = True
            title = extract_braced(stripped, "chapter*") or extract_braced(stripped, "chapter")
            if story:
                story.append(PageBreak())
            story.append(Paragraph(clean_tex(title), styles["Chapter"])); continue
        if not started:
            continue
        if stripped.startswith(r"\section"):
            flush_paragraph(); story.append(Paragraph(clean_tex(extract_braced(stripped, "section")), styles["Section"])); continue
        if stripped.startswith(r"\subsection"):
            flush_paragraph(); story.append(Paragraph(clean_tex(extract_braced(stripped, "subsection")), styles["Subsection"])); continue
        if stripped.startswith(r"\item"):
            flush_paragraph(); value = clean_tex(stripped[len(r"\item"):])
            story.append(Paragraph(value, styles["BulletVN"], bulletText="•")); continue
        if stripped.startswith(r"\reportimage"):
            flush_paragraph()
            parts = re.findall(r"\{([^{}]*)\}", stripped)
            caption = clean_tex(parts[-1]) if parts else "Ảnh minh họa giao diện"
            story.append(KeepTogether([Table([[Paragraph("VỊ TRÍ BỔ SUNG ẢNH CHỤP MÀN HÌNH", styles["CaptionVN"])]], colWidths=[14.8 * cm], rowHeights=[2.7 * cm], style=TableStyle([("BOX", (0, 0), (-1, -1), 0.7, colors.HexColor("#98A6B8")), ("BACKGROUND", (0, 0), (-1, -1), LIGHT_GRAY), ("VALIGN", (0, 0), (-1, -1), "MIDDLE")])), Paragraph(caption, styles["CaptionVN"])])); continue
        if stripped.startswith(r"\caption"):
            flush_paragraph(); story.append(Paragraph(clean_tex(extract_braced(stripped, "caption")), styles["CaptionVN"])); continue
        if not stripped:
            flush_paragraph(); continue
        if stripped.startswith("%") or re.match(r"^\\(begin|end|addcontentsline|clearpage|newpage|appendix|tableofcontents|listof|thispagestyle|vspace|small|centering)", stripped):
            flush_paragraph(); continue
        paragraph.append(stripped)
    flush_paragraph()
    return story


def build_pdf():
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    tex = TEX_FILE.read_text(encoding="utf-8")
    doc = ReportDocument(str(OUTPUT_FILE))
    toc = TableOfContents()
    toc.levelStyles = [
        ParagraphStyle(name="TOC0", fontName=SERIF_BOLD, fontSize=11, leading=17, leftIndent=0, firstLineIndent=0, textColor=BLUE),
        ParagraphStyle(name="TOC1", fontName=SERIF, fontSize=10, leading=15, leftIndent=16, firstLineIndent=0),
        ParagraphStyle(name="TOC2", fontName=SERIF, fontSize=9, leading=13, leftIndent=32, firstLineIndent=0),
    ]
    story = cover_story()
    story.extend([Paragraph("MỤC LỤC", styles["Chapter"]), toc, PageBreak()])
    story.extend(body_story(tex))
    doc.multiBuild(story)
    print(OUTPUT_FILE)


if __name__ == "__main__":
    build_pdf()
