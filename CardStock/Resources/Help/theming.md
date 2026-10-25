---
title: Change fonts, colors and layout
category: Theming
summary: Make the site look the way you want.
order: 1
---

Click **Configuration** in the sidebar. Below **Site Details**, the list has a page for each part of the look: **Template**, **Layout** (page width, and see [Page layouts](help:layouts)), **Fonts**, **Colors**, **Top Navigation Bar**, **Footer**, **Components**, **Mailing List** (see [Add a mailing list sign-up](help:newsletter)) and **Search** (see [Add search to your site](help:search)). Click one to see its settings on the right.

## See your changes

Click **Preview** (the sidebar button at the top right of the window) and a preview slides in on the right. It opens on the **Template** page: one page with every part of your style, such as colors, fonts, headings, lists, quotes, code, tables, buttons, the post list and product cards, between your site's top bar and footer. Every change shows straight away. Drag the line between the settings and the preview to resize them, and double-click it to split them evenly.

**Template** is also in [Pages](cardstock:pages), with the other pages. Its text shows under the title, so you can add anything you want to try out. It's only for the preview and is never published, and it can't be deleted. Its layout is `theme/template.html` in your site folder. Click a link in the preview's menu to see your other pages.

## Fonts

- **Body text** and **Headings** each have a font menu.
- **Text size** sets the main reading size.
- **Heading (H1) size** sets the size of page titles, in pixels.
- Want something not in the menu? See [Add a web font](help:web-fonts).

## Colors

1. Under **Appearance**, choose **Light**, **Dark** or **Auto**. Auto follows each visitor's device setting.
2. Pick colors for **Background**, **Cards and code blocks**, **Text**, **Secondary text**, **Accent and links**, and **Lines and borders**. With Auto you set both light and dark colors.

## Top navigation bar

The bar at the top of every page, with your logo or site title and the menu. Choose a **Style**:

- **Scrolls Away**: the bar is part of the page and scrolls off with it. This is how sites looked before.
- **Fixed**: the bar stays at the top of the window at one height, and the page scrolls behind it with a soft blur.
- **Shrinks on Scroll**: the bar starts tall with a big logo. As the page scrolls, it shrinks smoothly to **Height after scrolling**, and the logo shrinks to **Compact logo height**. Add a **Compact logo**, such as just an icon, and the big logo fades into it as the bar shrinks.

### Logo

1. Under **Logo**, next to **Image**, click **Choose Image…**. Pick an image from your site's Files, or click **Choose from Mac…** to copy one in.
2. Set its size. For SVG images, only **Height** shows: SVGs stay sharp at any size, and the width follows the logo's shape. For other images, type the **width** and **height** in pixels. With **Keep proportions** on, the other side changes to match, and **Actual Size** uses the image's own size.
3. **Description** is read aloud by screen readers when the site title isn't shown. Leave it empty to use the site title.
4. **Position** puts the logo and site title on the **Left**, in the **Center** or on the **Right** of the bar.
5. **Padding** adds space around them: type **Top**, **Right**, **Bottom** and **Left** in pixels.

**Show logo**, at the top, turns the logo off and on. While it's off, all your logo settings are kept for when you turn it back on. **Show site title** works the same way for the site's name. With either on, they sit in the chosen position; with both off, the bar shows just its links. With **Shrinks on Scroll**, you can also pick a **Compact logo** and its height.

**Dark mode logo** is a version of your logo for dark backgrounds, such as one with light lettering. When your site's appearance is Auto (Configuration → Colors), visitors whose device is set to dark see it instead of the main logo; when it's always Dark, it's the only one shown; when it's always Light, it isn't used. A compact logo can have a dark version too.

> For PNG or JPEG logos, use an image at least twice the size you show it at, so it's sharp on Retina screens.

### Links

The bar has three groups of links: **Left Links**, **Center Links** and **Right Links**. Turn on any of them, all three, or none. A group's links stay listed while it's off, so you can set them up first; they just don't show on your site.

1. In a group, click **Add Link**.
2. Type the text people see, such as `About`.
3. Type the address, such as `/pages/about/` for a page or a full `https://` address for another site, or click the page button next to it and choose one of your pages. If there's no page there yet, click **Create Page**.
4. Use the arrows to change the order, or **−** to remove a link.

Below each link, **Icon** adds an icon from CardStock's set (search, cart, email, social sites and more) before or after its text. Leave the link's text empty to show just the icon. Check **Button** to show the link as a button.

The logo goes before the links in its position, or after them on the right. Each page's address is shown under its title in [Pages](cardstock:pages).

**Phones**: on phones and other narrow screens (up to 600 pixels wide), the links fold into a menu button (☰) at the right of the bar. Tapping it shows every link, from all three groups, over the whole page, with buttons and icons as you set them; tapping a link or ✕ closes it. Turn off **Fold links into a menu on phones** to keep the links in the bar instead. To try it, pick a phone in the preview's device menu.

**Link Style**, below the groups, sets the links' **Font** (the headings font unless you pick another), **Size** and **Weight** (Regular, Semibold or Bold). It applies to all three groups. Fonts added on the Fonts page are in the menu too.

**Link Colors** sets the color of the links, of a link under the pointer (**Hover**), of the link to the page being viewed (**Current page**), of a link being clicked (**Click**) and of link icons (**Icons**), each with a **Light** and a **Dark** color. Click a swatch to pick a color, or type its hex value, such as `#1d1d1f`, next to it. Colors you haven't picked follow your site's colors and show their hex value in gray; click ↺ next to one, or clear its hex value, to go back to following them.

**Button Style** sets how every link with **Button** checked looks, in any group:

- **Background**, **Text**, **Border** and **Icon** colors, for Light and Dark. Until you pick them, buttons use your accent color with page-colored text, and icons match the text.
- **Border width**, and **Corners**: **Rounded** with a **Corner radius**, or **Fully Round**.
- **Background opacity** and **Background blur**. Lower the opacity and add blur for a frosted-glass button, especially in a Fixed or Shrinking bar over pictures.
- **Shadow**: None, Soft or Strong.
- **Icon position**: icons **Before Text** or **After Text**, for every top bar link with an icon.
- **Padding** inside the button.

## Footer

The line at the bottom of every page. [Footer](cardstock:footer) has a section for each part:

- **Show a footer**, at the top, turns it on or off.
- **Divider**: **Line at the top** turns the thin line above the footer on or off. **Space above line** is the gap between the page and the footer; **Padding below line** is the gap between the line and the footer's contents. **Reset to Default** puts the theme's spacing back.
- **Copyright**: **Copyright notice** shows © with the current year and your name. Leave **Name** empty to use the Author, or type something else, such as a business name.
- **Links**: **Add Link** adds Privacy Policy, Terms and Conditions, Contact, or any other link.
- **Buttons**: **Link to RSS feed** lets readers follow your blog in a news reader, and drop-down menus (below) open lists of links.
- **Logo**: an image at the start of the footer or below it (see below).
- **CardStock Attribution**: **Link to CardStock** adds a link to CardStock on GitHub, after your other links. It says **Designed with CardStock** unless you type your own text, and opens in a new window. It's off unless you turn it on.

If a link points to a page you haven't written yet, click **Create Page** next to it.

### Drop-down menus of links

A drop-down menu is a button next to **RSS** that opens a list of links, such as your YouTube, LinkedIn and Instagram pages.

1. In **Buttons**, click **Add Drop Menu…**. The first time, CardStock makes a link menu page called **Social Links** and opens it.
2. Put one link per line. Write `[YouTube](https://www.youtube.com/@you)` to choose the name, or just paste the address: `https://www.linkedin.com/in/you` shows as **LinkedIn**.
3. Back in **Buttons**, type the button's text, such as **Follow**, and pick which link menu it shows.

To make another list, click **New Page…** in [Pages](cardstock:pages) and choose **Link Menu**. Link menus show a link icon in the page list. They aren't published as pages of their own, and anything in them besides links is ignored.

### Footer logo

1. In **Logo**, next to **Image**, click **Choose Image…**.
2. Pick an image from your site's Files, or click **Choose from Mac…** to pick one from your Mac. CardStock copies it into Files (`media/files`) and uses the copy.
3. **Size** starts at the image's actual size in pixels. Type the width or height you want. With **Keep proportions** on, the other side changes to match. **Actual Size** puts it back. For SVG images, only **Height** shows (it starts at 100): SVGs stay sharp at any size and have no size in pixels of their own, so the width follows the logo's shape.
4. **Position**: **Left of the copyright** puts it at the start of the footer line. **Centered below** puts it on its own line under the footer, with **Space above** and **Space below** in pixels.
5. **Description** is read aloud by screen readers. Leave it empty to use the site title.

> For a sharp logo on Retina screens, use an image twice the size you show it at, such as a 240 × 80 image shown at 120 × 40.

> If your site was made with an older version of CardStock, footer, top bar and component changes won't show until you click **Update Theme Files** at the top of any look page in Configuration.

## Components

[Components](cardstock:components) sets the look of each building block of your pages. Watch the changes on the Template page in the preview.

- **Corners**: **Corner radius** is the starting point for every component's corners. **Apply Corners to All Components** sets them all from it. (The page's width is on the [Layout](cardstock:layouts) page.)
- **Buttons**: **Outline** or **Filled**, the corner radius, and the space inside. Buy buttons are always filled.
- **Cards**: product cards' corner radius, padding, border and shadow.
- **Image Corners**: rounding for cover images and for images in your text.
- **Code Blocks**: corner radius.
- **Quotes**: the color and width of the line beside a quote.
- **Tables**: shade every other row.
- **Drop-Down Menus**: corner radius of the footer's menus.

Every slider has **−** and **+** buttons for small steps.

**Reset to Defaults…** on the Template page puts everything back. To keep a look you like, save it as a [Template](help:styles) first.
