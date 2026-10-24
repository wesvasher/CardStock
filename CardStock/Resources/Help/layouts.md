---
title: Page layouts
category: Theming
summary: Arrange a page with a hero image, columns, a sidebar or full-width bands.
order: 4
---

A layout decides how a page is arranged: where the title goes, how wide the text is, and what sits around it. Your text stays plain Markdown. The layout only decides where it goes.

## Choose a page's layout

1. Open the page in [Pages](cardstock:pages).
2. Pick one from **Layout**, under **Type**. The preview changes straight away.

**Standard** is each page type's normal design. Every page uses it until you pick something else. An item's date, price and Buy button, and the lists on collection main pages and categories, show in every layout.

## The layouts

See them all in [Layout](cardstock:layouts) in Configuration. Click one to preview a sample page in it.

## Page width

The **Page** section at the top of [Layout](cardstock:layouts) applies to every page:

- **Content width**: the most the top bar, page and footer spread across a wide window. Pick a common width, such as **960 px** (the default), **640 px** for easy reading or **1140 px** for a wide site, or choose **Custom** and type any width in pixels. Narrower windows, like phones, always use their whole width.
- **Side padding**: the space kept at the window's edges.
- **Top bar and footer**: **Match Content** keeps them at the content width; **Full Width** lets them reach the window's edges.

| Layout | What it does | Areas |
|---|---|---|
| Wide | A wider column, for big images, tables and galleries | — |
| Hero | The title over a big cover image (or a band of your accent color), with an intro | Intro, Text |
| Sidebar | Your text with recent posts and blog categories beside it | Text, Sidebar |
| Two Columns | An intro across the top, then two columns | Intro, Left, Right |
| Landing | No title; each section is a full-width band, alternating colors | One band per section |

## Section breaks

Some layouts have more than one place for your text, called **areas**. A **section break** splits your text: the part after it goes into the next area.

1. Put the cursor where the next area should start.
2. Click the **section break** button in the formatting bar (the box split in two). It adds this line:

```
<!-- section -->
```

Without section breaks, all your text goes into the layout's main area, such as **Text** in Hero. If there are more sections than areas, the extra ones join the last area. In the Landing layout, every section becomes its own band.

Section breaks are invisible on the published site, and they do nothing in layouts with one area, so switching layouts never loses text.

## Add your own

Each layout is an HTML file in `theme/layouts` in your site folder. Click **Show Layouts Folder in Finder** on the Layouts page to find them. A new file there shows up in the Layout menus. The comment at the top of each file gives its name, description and areas.
