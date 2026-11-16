# Product

## Register

product

## Users

One person: a software engineer who works in Slack all day and keeps PlantUML and markdown notes in vault folders. They open Sequence between tasks to read or edit a diagram, and to check what is waiting on them in Slack. They lose track of threads and forget follow-ups; the board exists so that cannot happen.

## Product Purpose

Sequence is a personal Mac app to browse, view and edit PlantUML and markdown files, and to track Slack threads as tasks. Success is that nothing waiting on the user goes unnoticed: a glance at the board says what needs them now, what has new replies, and what has gone quiet.

## Brand Personality

Calm. Quiet surfaces and little noise, so a long list of threads does not stress the user. The one thing that needs attention is the clearest thing on the page; everything else recedes.

## Anti-references

Not specified by the owner. Standing rules from the project: no floating glass panels (the app deliberately avoids `NavigationSplitView` for this reason), and the default design bans apply (no side-stripe accents, no gradient text, no decorative glass or gradients).

## Design Principles

1. The next action is the loudest thing on the card; summaries and metadata recede.
2. Colour means something. Neutral by default, one warm accent for "needs attention", nowhere else.
3. Status is never shown by colour alone: every coloured chip carries a word.
4. Calm motion: no animation beyond an instant state change; nothing moves on its own.
5. Look native on macOS in both themes; every colour comes from `Theme.swift`.

## Accessibility & Inclusion

WCAG AA text contrast (4.5:1 body, 3:1 large) in both light and dark themes. Status and attention are conveyed with text or icons as well as colour. No required motion.
