# -*- coding: utf-8 -*-
"""Convert the snapshot customer runbook Markdown to .docx with the
'Microsoft Confidential - Customer Use' footer and numbered headings."""
import re
from docx import Document
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

SRC = r'd:\LearningProjects\BlockCopilotStudio\BlockCopilotStudioAccess\CUSTOMER-RUNBOOK-snapshot-2026-05-27.md'
OUT = r'd:\LearningProjects\BlockCopilotStudio\BlockCopilotStudioAccess\CUSTOMER-RUNBOOK-snapshot-2026-05-27.docx'

doc = Document()
# base font
normal = doc.styles['Normal']
normal.font.name = 'Calibri'; normal.font.size = Pt(11)

# footer on the default section
footer_p = doc.sections[0].footer.paragraphs[0]
footer_p.text = 'Microsoft Confidential — Customer Use'
footer_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for r in footer_p.runs:
    r.font.size = Pt(9); r.font.color.rgb = RGBColor(0x5A,0x67,0x70); r.font.name = 'Calibri'

INLINE = re.compile(r'(\*\*.+?\*\*|`[^`]+`)')
def add_formatted(p, text):
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith('**') and part.endswith('**'):
            run = p.add_run(part[2:-2]); run.bold = True
        elif part.startswith('`') and part.endswith('`'):
            run = p.add_run(part[1:-1]); run.font.name = 'Consolas'; run.font.size = Pt(10)
            run.font.color.rgb = RGBColor(0xC6,0x28,0x28)
        else:
            p.add_run(part)

def add_code(lines):
    for ln in lines:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Inches(0.25)
        p.paragraph_format.space_after = Pt(0)
        run = p.add_run(ln if ln else ' ')
        run.font.name = 'Consolas'; run.font.size = Pt(9.5)
        run.font.color.rgb = RGBColor(0x21,0x29,0x5C)

def add_table(rows):
    header = [c.strip() for c in rows[0].strip().strip('|').split('|')]
    body = [[c.strip() for c in r.strip().strip('|').split('|')] for r in rows[2:]]
    t = doc.add_table(rows=1, cols=len(header)); t.style = 'Light Grid Accent 1'
    for i, h in enumerate(header):
        cell = t.rows[0].cells[i]; cell.paragraphs[0].text = ''
        add_formatted(cell.paragraphs[0], h)
        for run in cell.paragraphs[0].runs: run.bold = True
    for r in body:
        cells = t.add_row().cells
        for i, c in enumerate(r):
            if i < len(cells):
                cells[i].paragraphs[0].text = ''
                add_formatted(cells[i].paragraphs[0], c)
    doc.add_paragraph()

lines = open(SRC, encoding='utf-8').read().splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    s = line.strip()
    # code fence (possibly indented under a list item)
    if s.startswith('```'):
        block = []
        i += 1
        while i < len(lines) and not lines[i].strip().startswith('```'):
            block.append(lines[i].strip() if lines[i].startswith('   ') else lines[i])
            i += 1
        add_code(block); i += 1; continue
    # table
    if s.startswith('|') and '|' in s[1:]:
        tbl = []
        while i < len(lines) and lines[i].strip().startswith('|'):
            tbl.append(lines[i]); i += 1
        add_table(tbl); continue
    # headings
    if s.startswith('### '):
        h = doc.add_heading(level=2); add_formatted(h, s[4:]); i += 1; continue
    if s.startswith('## '):
        h = doc.add_heading(level=1); add_formatted(h, s[3:]); i += 1; continue
    if s.startswith('# '):
        h = doc.add_heading(level=0); add_formatted(h, s[2:]); i += 1; continue
    # horizontal rule
    if s == '---':
        i += 1; continue
    # blockquote callout
    if s.startswith('>'):
        p = doc.add_paragraph(); p.paragraph_format.left_indent = Inches(0.2)
        add_formatted(p, s.lstrip('> ').rstrip());
        for r in p.runs: r.italic = True
        i += 1; continue
    # bullet
    if s.startswith('- '):
        p = doc.add_paragraph(style='List Bullet'); add_formatted(p, s[2:]); i += 1; continue
    # numbered step
    m = re.match(r'^(\d+)\.\s+(.*)', s)
    if m:
        p = doc.add_paragraph(); add_formatted(p, f"{m.group(1)}. {m.group(2)}")
        i += 1; continue
    # blank
    if s == '':
        i += 1; continue
    # paragraph
    p = doc.add_paragraph(); add_formatted(p, s); i += 1

doc.save(OUT)
print('SAVED', OUT)
