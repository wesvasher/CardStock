---
title: Add a mailing list sign-up
category: Writing
summary: Put a sign-up form from your newsletter service on any page.
order: 7
---

CardStock doesn't send newsletters itself. It shows the sign-up form from the service you use, such as Buttondown, Kit, Mailchimp, beehiiv or Substack, in a box you can put on any page.

## Set it up

1. In your newsletter service, find its embed code. Look for **Embed**, **Embedded form** or **Share** in its settings. It's a piece of HTML, such as an `<iframe>`, or a `<form>` with a `<script>`.
2. Copy it, then open [Mailing List](cardstock:newsletter) in Configuration.
3. Paste it under **Sign-Up Form**.
4. Under **Box**, set the **Heading** and **Text** shown above the form. Leave them empty if the embed code has its own. **Card** puts the box in a card, using the card look from [Components](cardstock:components); **Plain** puts it straight on the page. **Alignment** puts it on the left or in the center.

Click **Preview** at the top right to see the box on a sample page.

## Put it on a page

1. Open a page in [Pages](cardstock:pages).
2. Click where the box should go, on its own line.
3. Click the envelope button in the formatting bar.

That adds a `<!-- newsletter -->` line, highlighted in the editor. On your site, the box shows in its place. You can add it to as many pages as you like, and the **Pages** list on the Mailing List page shows where it is. Changing the box in Configuration changes it everywhere.

> Some services' forms only work on your live site, so the preview may show an empty space or an error. Publish and check the page online.

Until there's embed code, the preview shows a note where the box goes, the box is left out of your published site, and the Start screen's health checklist reminds you.
