# -*- coding: utf-8 -*-
"""Build the Tenant Change Response deck for the Copilot Studio lockdown.
Follows csa-deliverable-style: Ocean Gradient palette, <=3 lines body text,
one primary visual per slide, footer once, DRAFT marker."""
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml.ns import qn

# ---- palette ----
PRIMARY   = RGBColor(0x06,0x5A,0x82)
SECONDARY = RGBColor(0x1C,0x72,0x93)
ACCENT    = RGBColor(0x21,0x29,0x5C)
SURFACE   = RGBColor(0xF5,0xF7,0xFA)
TEXT_DARK = RGBColor(0x21,0x21,0x21)
TEXT_MUT  = RGBColor(0x5A,0x67,0x70)
GREEN     = RGBColor(0x2E,0x7D,0x32)
AMBER     = RGBColor(0xF5,0x7F,0x17)
RED       = RGBColor(0xC6,0x28,0x28)
ORANGE    = RGBColor(0xE6,0x51,0x00)
WHITE     = RGBColor(0xFF,0xFF,0xFF)
DIVIDER   = RGBColor(0xE0,0xE0,0xE0)
# heatmap tints
TINT_CRIT = RGBColor(0xE2,0xA4,0xA6)
TINT_HIGH = RGBColor(0xF2,0xBB,0x99)
TINT_MED  = RGBColor(0xF8,0xC6,0x90)
TINT_LOW  = RGBColor(0xA5,0xC6,0xAA)

FONT = "Calibri"
CUSTOMER = "Customer"
DATE = "2026-05-27"

SW, SH = Inches(13.333), Inches(7.5)
prs = Presentation()
prs.slide_width = SW; prs.slide_height = SH
BLANK = prs.slide_layouts[6]

def bg(slide, color=SURFACE):
    slide.background.fill.solid()
    slide.background.fill.fore_color.rgb = color

def _set_font(run, size, bold=False, color=TEXT_DARK, font=FONT):
    run.font.size = Pt(size); run.font.bold = bold
    run.font.color.rgb = color; run.font.name = font

def textbox(slide, l,t,w,h, lines, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, wrap=True):
    """lines: list of (text,size,bold,color) ; returns shape"""
    tb = slide.shapes.add_textbox(l,t,w,h); tf = tb.text_frame
    tf.word_wrap = wrap; tf.vertical_anchor = anchor
    tf.margin_left=Inches(0.05); tf.margin_right=Inches(0.05)
    tf.margin_top=Inches(0.02); tf.margin_bottom=Inches(0.02)
    for i,(txt,sz,bold,col) in enumerate(lines):
        p = tf.paragraphs[0] if i==0 else tf.add_paragraph()
        p.alignment = align
        r = p.add_run(); r.text = txt
        _set_font(r,sz,bold,col)
    return tb

def title(slide, text):
    textbox(slide, Inches(0.5), Inches(0.28), Inches(12.33), Inches(0.7),
            [(text,32,True,PRIMARY)], anchor=MSO_ANCHOR.MIDDLE)
    # subtle divider under title
    ln = slide.shapes.add_connector(2, Inches(0.5), Inches(1.02), Inches(12.83), Inches(1.02))
    ln.line.color.rgb = DIVIDER; ln.line.width = Pt(1)

def footer(slide, page, extra_author=False):
    txt = f"Microsoft CSA Assessment · {CUSTOMER} · " + (f"Sayed Ali · " if extra_author else "") + f"{DATE} · DRAFT"
    ln = slide.shapes.add_connector(2, Inches(0.5), Inches(7.0), Inches(12.83), Inches(7.0))
    ln.line.color.rgb = DIVIDER; ln.line.width = Pt(1)
    textbox(slide, Inches(0.5), Inches(7.05), Inches(10.5), Inches(0.35),
            [(txt,10,False,TEXT_MUT)], anchor=MSO_ANCHOR.MIDDLE)
    textbox(slide, Inches(11.5), Inches(7.05), Inches(1.33), Inches(0.35),
            [(str(page),10,False,TEXT_MUT)], align=PP_ALIGN.RIGHT, anchor=MSO_ANCHOR.MIDDLE)

def rect(slide, l,t,w,h, fill, line=None, rounded=False):
    shp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE if rounded else MSO_SHAPE.RECTANGLE, l,t,w,h)
    shp.fill.solid(); shp.fill.fore_color.rgb = fill
    if line is None:
        shp.line.fill.background()
    else:
        shp.line.color.rgb = line; shp.line.width = Pt(1)
    shp.shadow.inherit = False
    return shp

def card(slide, l,t,w,h, lines, fill=WHITE, line=DIVIDER, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.MIDDLE, pad=0.15):
    r = rect(slide,l,t,w,h,fill,line,rounded=True)
    tf = r.text_frame; tf.word_wrap=True; tf.vertical_anchor=anchor
    tf.margin_left=Inches(pad); tf.margin_right=Inches(pad)
    tf.margin_top=Inches(0.08); tf.margin_bottom=Inches(0.08)
    for i,(txt,sz,bold,col) in enumerate(lines):
        p = tf.paragraphs[0] if i==0 else tf.add_paragraph()
        p.alignment = align
        rn = p.add_run(); rn.text = txt
        _set_font(rn,sz,bold,col)
    return r

def circle(slide, l,t,d, fill, glyph, gsize=20, gcolor=WHITE):
    c = slide.shapes.add_shape(MSO_SHAPE.OVAL, l,t,Inches(d),Inches(d))
    c.fill.solid(); c.fill.fore_color.rgb=fill; c.line.fill.background(); c.shadow.inherit=False
    tf=c.text_frame; tf.word_wrap=False; tf.vertical_anchor=MSO_ANCHOR.MIDDLE
    p=tf.paragraphs[0]; p.alignment=PP_ALIGN.CENTER
    r=p.add_run(); r.text=glyph; _set_font(r,gsize,True,gcolor)
    return c

# ============================================================ SLIDE 1 — Title
s = prs.slides.add_slide(BLANK); bg(s, ACCENT)
textbox(s, Inches(0.8), Inches(1.9), Inches(11.7), Inches(1.4),
        [("Locking Down Copilot Studio Access",44,True,WHITE)], anchor=MSO_ANCHOR.MIDDLE)
textbox(s, Inches(0.8), Inches(3.25), Inches(11.7), Inches(0.9),
        [("Block Copilot Studio for all users — allow only the 'Copilot Studio Authors' group",18,False,SURFACE)],
        anchor=MSO_ANCHOR.MIDDLE)
# status chip (amber) — honesty rule
chip = rect(s, Inches(0.8), Inches(4.45), Inches(9.7), Inches(0.95), AMBER, rounded=True)
tf=chip.text_frame; tf.word_wrap=True; tf.vertical_anchor=MSO_ANCHOR.MIDDLE
tf.margin_left=Inches(0.2)
p=tf.paragraphs[0]; r=p.add_run(); r.text="Community workaround — not a Microsoft-supported solution (Layer 1)"
_set_font(r,17,True,WHITE)
p2=tf.add_paragraph(); r2=p2.add_run(); r2.text="Layers 2 & 3 are Microsoft-supported"
_set_font(r2,12,False,WHITE)
# footer (with author on title slide only)
footer(s,1,extra_author=True)

# ============================================================ SLIDE 2 — Challenge
s = prs.slides.add_slide(BLANK); bg(s); title(s,"The Challenge")
# big stat
textbox(s, Inches(0.8), Inches(1.7), Inches(3.2), Inches(2.2),
        [("3",110,True,PRIMARY)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
textbox(s, Inches(0.8), Inches(3.9), Inches(3.2), Inches(0.8),
        [("independent access paths",16,True,SECONDARY)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.TOP)
# right cards
card(s, Inches(4.4), Inches(1.7), Inches(8.1), Inches(1.0),
     [("Unlicensed users reach copilotstudio.microsoft.com",16,True,TEXT_DARK),
      ("Shadow agents created outside governance",13,False,TEXT_MUT)])
card(s, Inches(4.4), Inches(2.85), Inches(8.1), Inches(1.0),
     [("Same users self-create Teams / Power Platform environments",16,True,TEXT_DARK),
      ("Sprawl and ungoverned Dataverse data",13,False,TEXT_MUT)])
card(s, Inches(4.4), Inches(4.0), Inches(8.1), Inches(1.0),
     [("The PPAC 'authors' setting alone does not revoke access",16,True,RED),
      ("Any one of the 3 grant paths is enough — one control never blocks",13,False,TEXT_MUT)])
footer(s,2)

# ============================================================ SLIDE 3 — Root Cause
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Root Cause — Microsoft's access model")
card(s, Inches(0.8), Inches(1.5), Inches(11.7), Inches(0.85),
     [("Copilot Studio access is granted if ANY of these is true:",18,True,PRIMARY)], anchor=MSO_ANCHOR.MIDDLE)
for i,(num,txt) in enumerate([("1","Member of the Copilot Studio authors group"),
                              ("2","Has a Copilot Studio per-user or trial license"),
                              ("3","Has a Microsoft 365 Copilot license")]):
    x = Inches(0.8 + i*3.95)
    circle(s, x, Inches(2.6), 0.55, SECONDARY, num, 22)
    card(s, x, Inches(3.3), Inches(3.7), Inches(1.15), [(txt,14,False,TEXT_DARK)], anchor=MSO_ANCHOR.MIDDLE)
# no supported portal-lock note
card(s, Inches(0.8), Inches(4.75), Inches(11.7), Inches(0.85),
     [("Microsoft documents NO supported way to lock the portal via enterprise-app settings (Layer 1).",15,True,ORANGE)],
     fill=RGBColor(0xFD,0xF3,0xE6), line=AMBER, anchor=MSO_ANCHOR.MIDDLE)
# citation
textbox(s, Inches(0.8), Inches(5.75), Inches(11.7), Inches(0.9),
        [("Source: learn.microsoft.com/troubleshoot/power-platform/copilot-studio/licensing/authors-access",11,False,TEXT_MUT),
         ("Status: GA · Retrieved 2026-05-27 · Confidence: tenant-verified (M365CPI90282478)",11,True,GREEN)])
footer(s,3)

# ============================================================ SLIDE 3b — Documented != Actual
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Documented ≠ Actual — verified in tenant")
# left: documented
rect(s, Inches(0.8), Inches(1.5), Inches(5.75), Inches(0.6), SECONDARY, rounded=True).text_frame.paragraphs[0].add_run().text=""
textbox(s, Inches(0.9), Inches(1.55), Inches(5.55), Inches(0.5),[("Microsoft documents",16,True,WHITE)],anchor=MSO_ANCHOR.MIDDLE)
card(s, Inches(0.8), Inches(2.2), Inches(5.75), Inches(2.4),
     [("Removing the Copilot Studio license / service plan removes the user's Copilot Studio access.",15,False,TEXT_DARK)],
     anchor=MSO_ANCHOR.MIDDLE)
# right: actual
rect(s, Inches(6.78), Inches(1.5), Inches(5.75), Inches(0.6), RED, rounded=True)
textbox(s, Inches(6.88), Inches(1.55), Inches(5.55), Inches(0.5),[("Verified in tenant · 2026-05-27",16,True,WHITE)],anchor=MSO_ANCHOR.MIDDLE)
card(s, Inches(6.78), Inches(2.2), Inches(5.75), Inches(2.4),
     [("HadarC's Copilot Studio service plan is ALREADY disabled — yet access persists.",15,True,RED),
      ("Why: still in the authors group + holds an Enabled Power Apps service plan.",13,False,TEXT_MUT)],
     anchor=MSO_ANCHOR.MIDDLE)
# bottom takeaway
card(s, Inches(0.8), Inches(4.8), Inches(11.73), Inches(1.15),
     [("Takeaway: remove license AND remove from the group — co-equal required steps; neither alone is enough.",15,True,PRIMARY),
      ("Also verified: allowedToSignUpEmailBasedSubscriptions = True (allowed). Set $false to block.",12,False,TEXT_MUT)],
     fill=RGBColor(0xEC,0xF2,0xF6), line=SECONDARY, anchor=MSO_ANCHOR.MIDDLE)
footer(s,4)

# ============================================================ SLIDE 4 — Fix Approach
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Fix Approach — layered defense")
steps = [("3","Tenant flags","Block non-admin env creation (prod / trial / dev)",GREEN,"Supported"),
         ("2","Block trials","Remove Internal+Viral consent plans + Entra sign-up flag",GREEN,"Supported"),
         ("1","Portal lock","Restrict the 2 CPS apps to the Authors group only",AMBER,"Unsupported"),
         ("✓","Access","Grant = add to group; revoke = remove + clear license",SECONDARY,"Operate")]
for i,(num,head,desc,col,tag) in enumerate(steps):
    x = Inches(0.7 + i*3.05)
    circle(s, Inches(0.7+i*3.05+1.0), Inches(1.5), 0.7, col, num, 26)
    c = card(s, x, Inches(2.45), Inches(2.85), Inches(2.6),
         [(head,17,True,col),(desc,13,False,TEXT_DARK)], anchor=MSO_ANCHOR.TOP)
    # tag at bottom
    textbox(s, x, Inches(4.65), Inches(2.85), Inches(0.35),[(tag.upper(),11,True,col)],align=PP_ALIGN.CENTER)
footer(s,5)

# ============================================================ SLIDE 5 — How It Works (diagram)
s = prs.slides.add_slide(BLANK); bg(s); title(s,"How It Works")
from PIL import Image
img = "diagram-cps-lockdown-2026-05-27.png"
iw,ih = Image.open(img).size
maxw, maxh = Inches(12.0), Inches(5.55)
ar = iw/ih
w = maxw; h = Emu(int(w/ar))
if h > maxh:
    h = maxh; w = Emu(int(h*ar))
left = Emu(int((SW - w)/2)); top = Inches(1.25)
s.shapes.add_picture(img, left, top, width=w, height=h)
footer(s,6)

# ============================================================ SLIDE 6 — Risk Heatmap
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Risk Assessment")
# 3x3 grid: x=likelihood(1..3), y=impact(3..1 top->bottom)
gx0, gy0 = Inches(2.4), Inches(1.55)
cell = Inches(2.4); cellh = Inches(1.5)
def sev(l,i):
    z = l+i
    if l==3 and i==3: return TINT_CRIT
    if z>=5: return TINT_HIGH
    if z>=3 and not (l==1 and i==1):
        return TINT_MED if (l+i)>=4 or (l>=2 and i>=2) or i==3 or l==3 else TINT_LOW
    return TINT_LOW
# explicit zone map per brief
zone = {(3,3):TINT_CRIT,(2,3):TINT_HIGH,(3,2):TINT_HIGH,
        (1,3):TINT_MED,(2,2):TINT_MED,(3,1):TINT_MED,
        (1,1):TINT_LOW,(1,2):TINT_LOW,(2,1):TINT_LOW}
for ix,l in enumerate([1,2,3]):
    for iy,i in enumerate([3,2,1]):
        x = Emu(int(gx0)+ix*int(cell)); y=Emu(int(gy0)+iy*int(cellh))
        rect(s, x, y, cell, cellh, zone[(l,i)], line=RGBColor(0xD0,0xD3,0xE0))
# axis labels
textbox(s, Inches(0.6), Inches(1.55), Inches(1.7), Inches(4.5),
        [("Impact → High",12,True,TEXT_MUT),("",12,False,TEXT_MUT),("Med",12,True,TEXT_MUT),("",12,False,TEXT_MUT),("Low",12,True,TEXT_MUT)],
        align=PP_ALIGN.RIGHT)
textbox(s, Inches(2.4), Inches(6.1), Inches(7.2), Inches(0.4),
        [("Likelihood:   Low            Medium            High",12,True,TEXT_MUT)])
# dots: (likelihood,impact) -> label
dots = {(3,3):["R1"],(2,3):["R2"],(1,3):["R3"],(2,2):["R4","R5","R6"]}
dotcol = {"R1":RED,"R2":ORANGE,"R3":ORANGE,"R4":AMBER,"R5":AMBER,"R6":AMBER}
for (l,i),labels in dots.items():
    ix=[1,2,3].index(l); iy=[3,2,1].index(i)
    cx = int(gx0)+ix*int(cell); cy=int(gy0)+iy*int(cellh)
    n=len(labels)
    for k,lab in enumerate(labels):
        dx = cx + int(cell)/2 - (n*int(Inches(0.55)))/2 + k*int(Inches(0.55)) - int(Inches(0.0))
        circle(s, Emu(int(dx)), Emu(int(cy+int(cellh)/2-int(Inches(0.27)))), 0.5, dotcol[lab], lab, 13)
# legend
leg = [("R1  M365 Copilot license bypasses group (Critical)",RED),
       ("R2  MS may change first-party app behavior (High)",ORANGE),
       ("R3  Locking CPS Service app may break agents (High)",ORANGE),
       ("R4 appId undocumented · R5 broad trial block · R6 no -WhatIf (Med)",AMBER)]
ly=Inches(1.6)
for txt,col in leg:
    circle(s, Inches(9.85), ly, 0.22, col, "", 8)
    textbox(s, Inches(10.15), ly, Inches(3.0), Inches(0.5),[(txt,10,False,TEXT_DARK)],anchor=MSO_ANCHOR.MIDDLE)
    ly = Emu(int(ly)+int(Inches(0.62)))
footer(s,7)

# ============================================================ SLIDE 7 — Impact / Blast Radius
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Impact / Blast Radius")
rows = [("Change","Scope","Side effects beyond the goal",PRIMARY,WHITE,True),
        ("Disable non-admin env creation","All non-admins","Blocks ALL Power Platform env creation; existing kept",None,None,False),
        ("Remove Internal+Viral consent plans","Tenant-wide","Stops self-service trials for ALL PP products",None,None,False),
        ("allowedToSignUpEmailBasedSubscriptions=$false","Tenant-wide","Blocks email-based self-service sign-up org-wide",None,None,False),
        ("AppRoleAssignmentRequired on 2 apps","PVA + CPS Service","Global Admins exempt; may affect existing agents; unsupported",AMBER,None,False)]
ry = Inches(1.5); cols=[Inches(0.8),Inches(4.7),Inches(7.3)]; widths=[Inches(3.8),Inches(2.5),Inches(5.23)]
rh = Inches(1.0)
for ri,(c1,c2,c3,fill,tcol,hdr) in enumerate(rows):
    h = Inches(0.55) if hdr else rh
    f = fill if fill else (WHITE if ri%2 else RGBColor(0xEE,0xF1,0xF5))
    is_amber = (fill == AMBER)
    for ci,(txt,w) in enumerate(zip((c1,c2,c3),widths)):
        col = WHITE if (hdr or is_amber) else (tcol if tcol else TEXT_DARK)
        bold = hdr or ci==0
        cc = card(s, cols[ci], ry, w, h, [(txt, 12 if not hdr else 13, bold, col)],
                  fill=f, line=DIVIDER, anchor=MSO_ANCHOR.MIDDLE, pad=0.12)
    ry = Emu(int(ry)+int(h)+int(Inches(0.08)))
footer(s,8)

# ============================================================ SLIDE 8 — Permissions
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Permissions Needed")
# two columns
rect(s, Inches(0.8), Inches(1.5), Inches(5.75), Inches(0.6), PRIMARY, rounded=True)
textbox(s, Inches(0.9), Inches(1.55), Inches(5.55), Inches(0.5),[("Admin roles",16,True,WHITE)],anchor=MSO_ANCHOR.MIDDLE)
rect(s, Inches(6.78), Inches(1.5), Inches(5.75), Inches(0.6), SECONDARY, rounded=True)
textbox(s, Inches(6.88), Inches(1.55), Inches(5.55), Inches(0.5),[("Graph scopes / cmdlet rights",16,True,WHITE)],anchor=MSO_ANCHOR.MIDDLE)
roles = ["Global Administrator","Power Platform Administrator","(grant/revoke) Group writer"]
rights = ["Application.ReadWrite.All · AppRoleAssignment.ReadWrite.All · Group.Read.All",
          "Add-PowerAppsAccount · Set-TenantSettings · Remove-AllowedConsentPlans",
          "Policy.ReadWrite.Authorization (new) · Group.ReadWrite.All · User.Read.All"]
y=Inches(2.25)
for r in roles:
    card(s, Inches(0.8), y, Inches(5.75), Inches(1.0),[(r,14,True,TEXT_DARK)],anchor=MSO_ANCHOR.MIDDLE)
    y=Emu(int(y)+int(Inches(1.15)))
y=Inches(2.25)
for r in rights:
    card(s, Inches(6.78), y, Inches(5.75), Inches(1.0),[(r,12,False,TEXT_DARK)],anchor=MSO_ANCHOR.MIDDLE)
    y=Emu(int(y)+int(Inches(1.15)))
footer(s,9)

# ============================================================ SLIDE 9 — Prerequisites
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Prerequisites")
items = [("✓","'Copilot Studio Authors' security group exists",GREEN),
         ("✓","PowerShell modules incl. Microsoft.Graph.Identity.SignIns (new)",GREEN),
         ("!","Decide handling of Microsoft 365 Copilot–licensed users",AMBER),
         ("✓","Expect 2 interactive sign-ins (Power Platform + Graph)",GREEN),
         ("!","Run in a change window — Layer 1 touches first-party apps",AMBER)]
y=Inches(1.6)
for glyph,txt,col in items:
    circle(s, Inches(1.0), y, 0.5, col, glyph, 20)
    card(s, Inches(1.7), y, Inches(10.6), Inches(0.85),[(txt,15,False,TEXT_DARK)],anchor=MSO_ANCHOR.MIDDLE)
    y=Emu(int(y)+int(Inches(1.02)))
footer(s,10)

# ============================================================ SLIDE 10 — Rollback & Next Steps
s = prs.slides.add_slide(BLANK); bg(s); title(s,"Rollback & Next Steps")
# horizontal timeline
phases=[("APPLY","Run lockdown script\n(+ Entra flag step)",PRIMARY),
        ("VERIFY","Read-only probes +\nmanual sign-in (T1/T2)",SECONDARY),
        ("ROLLBACK","Flags→false · re-add plans ·\nAppRoleReq→false",ORANGE),
        ("NEXT","Add -WhatIf · log M365\nCopilot decision · re-check appIds",GREEN)]
# connector line
ln = s.shapes.add_connector(2, Inches(1.2), Inches(3.0), Inches(12.1), Inches(3.0))
ln.line.color.rgb = TEXT_MUT; ln.line.width = Pt(2)
for i,(head,desc,col) in enumerate(phases):
    cx = Inches(1.5 + i*3.0)
    circle(s, cx, Inches(2.7), 0.6, col, str(i+1), 22)
    textbox(s, Emu(int(cx)-int(Inches(1.0))), Inches(3.5), Inches(2.6), Inches(0.5),
            [(head,15,True,col)],align=PP_ALIGN.CENTER)
    card(s, Emu(int(cx)-int(Inches(1.0))), Inches(4.05), Inches(2.6), Inches(1.5),
         [(desc.replace("\n"," "),12,False,TEXT_DARK)],anchor=MSO_ANCHOR.MIDDLE,align=PP_ALIGN.CENTER)
footer(s,11)

prs.save("presentation-cps-lockdown-2026-05-27.pptx")
print("SAVED presentation-cps-lockdown-2026-05-27.pptx with", len(prs.slides._sldIdLst), "slides")
