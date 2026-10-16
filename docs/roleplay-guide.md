# How to prompt for roleplay

Play the life you want, with a story and finances that agree. The same topics are available through the in-app roleplay guide. Adapt examples to the current game date, accounting currency, and recorded accounts.

## Choose how this life plays

**Simulation** resolves attempts through the world's rules and uncertain outcomes. **Sandbox** accepts player-declared fictional outcomes while the engine validates dates, money, ownership, and records. Difficulty controls uncertain challenges separately from play style. The Swing Dial controls how strange the story can be.

An approved starting background is already established. Distinguish it from what happens next:

> My approved background is membership in a fictional royal family. My family covers my home and living costs; family wealth is separate from my personal cash. I ask my cousin to introduce me to a business mentor.

## Choose a nation and effective date

Choose the nation and applicable region from presets when starting a life, moving, or creating a business. Cities and neighborhoods can be described freely; their names do not replace the saved jurisdiction. Your residence, a company's jurisdiction, and an employee's work jurisdiction can differ.

> From 2004-11-13, the incorporated website business operates in Texas, United States. I still live in Texas. Keep its business account separate from my personal funds.

Tax profiles identify sourced rules and estimates for the story's date. Historical gaps and future projections remain labeled estimates. Check the chosen preset and assumptions; moving does not rewrite prior transactions or change the life's accounting currency.

## Distinguish revenue from profit

Revenue is sales before payroll, operating costs, and business taxes. Net profit remains after those costs. State the business, currency, monthly amount, receiving account, and effective date. A recurring rate is not an immediate deposit.

> In Sandbox, my incorporated website now earns USD 50,000 gross revenue each month, before payroll, hosting, and taxes. Record this from the current game date in the website's business account. Replace its previous revenue rate; do not also add a net-profit income stream or a lump-sum deposit.

In Simulation, describe the work and target, then record the result actually established. Existing net-income streams retain their original meaning until explicitly converted from a chosen date. Do not deduct payroll and expenses twice from an amount already stated as net profit. Use the life's accounting currency rather than silently converting amounts.

## Record employees and your salary

Specify gross monthly pay, work jurisdiction, business funding account, and employment start/end dates. Staff with identical terms can share a group record with headcount and **pay per person**. Missing wages must be supplied before payroll can be configured.

> Starting today, employ two developers in Texas at USD 4,000 gross per person per month, paid from the website business account. My gross owner salary is USD 1,500 per month from that account into my personal account. Apply the recorded employee deductions and employer charges. Do not invent other staff or wages.

Gross salary and take-home pay differ when deductions apply. Owner salary is funded by the company; it must not also appear as an unfunded personal income stream. Insufficient business funds create visible unpaid obligations rather than silently draining personal savings.

## Record expenses, raises, and departures

Give recurring expenses stable names, amounts, business accounts, and effective dates within the current turn. Specify whether an agreement starts, changes, or ends. A rate change does not rewrite settled months.

> From the current game date, change hosting to USD 800 per month and raise both developers to USD 4,500 gross each. Keep the existing payroll records and change their rates from today. Do not create duplicate employees.

> Nora's employment ends on the current game date. End her payroll record and keep the wages already earned or still unpaid in the records.

## Keep personal and company funds separate

Name the account when spending or transferring. Family support and access to family property are not personal cash. A transfer needs available, accessible funds and is not new income.

> Transfer USD 10,000 from my website's business account to my personal account as an owner's draw. Use existing business funds. This is a transfer, not new revenue, a gift, or another salary payment.

To close an account, specify where its remaining money goes and how linked obligations are resolved. Choose a replacement before closing the default personal account. Closed or transferred accounts retain their history but cannot fund new actions.

## Review a company sale

Specify the company, buyer, price, effective date, and proceeds account. Review the proposal before confirming: taxes, transferred accounts and obligations, and any retained rights matter.

> Prepare a sale of my entire website company to Northbridge for USD 2 million, effective on the current game date. Show the tax estimate and the company accounts and obligations that transfer. Put the sale proceeds into my personal account after I confirm the review.

A completed full sale removes access to company money. Its cash is not a second personal payout on top of the sale price. Do not assume continuing wages, ownership, or management access unless the reviewed terms support them. If the save changes before confirmation, review refreshed terms.

## Advance time and check the actual records

First verify the recurring revenue, payroll, and expenses are recorded. Give an exact skip duration and its focus:

> Skip exactly three months. Maintain the recorded website revenue, payroll, operating costs, owner salary, and living arrangement. Apply obligations due during this period. Keep company proceeds in the business account.

New business obligations accrue during the month and settle on the first of the following month, with partial months prorated. Legacy net-income streams retain their original month-boundary timing. A zero-time action does not create monthly cash, and a new agreement does not imply undocumented back pay.

Check **Finances** after important changes. Compare revenue, payroll, taxes, unpaid obligations, available balances, and ledger entries with the story. Business obligations and legacy income streams are different records. `((accounts))` answers from saved accounts without calling the narrator or advancing time; `((income))` reports legacy income streams.

## Correct a mismatch explicitly

Use finance controls to inspect and change businesses, obligations, accounts, or legacy income. Choose an effective date and name the record being replaced. You can also ask through roleplay:

> My website's gross monthly revenue should be USD 50,000 from the current game date. My gross owner salary should be USD 1,500 funded by that business. Correct those records, end any duplicate net-income stream from the same date, and leave already-settled history unchanged.

**Retry reply** resubmits a failed action with its original time skip and reply length. It does not undo a saved scene. Edit the action to change the request; editing or changing story settings clears a pending retry.

## Help the narrator find earlier context

Name the person or company and roughly when an agreement occurred:

> Remember the payroll agreement I made with Nora last May. Show how this month's expansion affects that agreement, using the recorded wages and dates.

In **Life & story settings → Look up earlier records**, choose:

- **Automatic:** ask for relevant older records on financial/business actions, time skips, and references to past events.
- **Always:** make a selection request before each turn when older records are available.
- **Off:** use local relevance matching without another model request.

Current dates, finances, account access, relationships, and active obligations are always included. Lookup only selects records from the active life; it does not change the save. Each lookup counts toward API usage even when the main reply fails. A failed lookup uses locally matched history, with context-coverage notices outside the story. Prose drafting remains separate and can add its own request.

## Tell the narrator what you enjoy

Specify pace, perspective, tone, and desired scenes separately from financial instructions.

> Keep the story hopeful and ambitious, with short scenes and natural dialogue. Let me choose my character's words and decisions. When money changes, make the prose agree with the recorded accounts and explain any constraint plainly.
