---
title: Sell with Stripe Payment Links
category: Writing
summary: Choose a checkout service in Configuration → Shopping, then add Buy buttons to any page.
order: 21
---

Your site is plain web pages, so it can't take payments by itself. A checkout service does that for you. Choose one in [Shopping](cardstock:shopping) in Configuration. For now CardStock works with **Stripe Payment Links**.

## What Stripe Payment Links are

A Payment Link is a web address Stripe makes for one product, like `https://buy.stripe.com/…`. On your site it's a **Buy button**. Clicking it opens Stripe's secure checkout page in a new tab, where buyers pay by card, Apple Pay and more. Stripe sends you the money and the receipt. CardStock never sees payments or card details.

There's no shopping cart: each button buys one product. Stripe's page can let buyers choose how many.

## Set it up

1. Open [Shopping](cardstock:shopping) in Configuration and choose **Stripe Payment Links**.
2. In your Stripe Dashboard, open **Payment Links** and click **New**. Pick a product and price, or add one.
3. Click **Create link** and copy the link.

Making a Stripe account is free. Stripe takes a fee from each sale.

## Add a Buy button to a page

Once Stripe Payment Links is on, there are two ways:

- **Anywhere in the text**: click where the button should go, then click the cart button in the formatting bar. Paste the link, change the button's text if you like, and click **Add Button**. This adds a line like `<!-- buy https://buy.stripe.com/… "Buy the print" -->`, which shows as the button.
- **After the page's text**: open **Page Settings** and paste the link in **Payment link**. **Button** changes its text.

Buttons use your button style from [Components](cardstock:components). The text new buttons start with is set in Shopping.

> Test your links with Stripe's test mode first: test links work like real ones, but no money changes hands.

## Shop items

Items in a collection that sells, like the Shop, already have **Price**, **Buy link** and **Button** in their editor. Paste a Payment Link in **Buy link**. These work whichever checkout service you choose. Learn more in [Collections](help:collections).

## Turning it off

Choose **None** in Shopping. Buttons typed into a page's text still show. Payment links in Page Settings stop showing until you choose Stripe Payment Links again.
