# Business accounting

LifeGPT's business engine is a deterministic simulation. The narrator proposes dated facts; the engine calculates money movements, records obligations, and validates the complete turn before the store commits anything. Country coverage and statutory verification are separate: inspect each fiscal profile's evidence and the settlement's assumptions.

## Gross revenue, salaries, and personal funds

A business owns an operating account. A recurring revenue record deposits gross revenue monthly in arrears, on the next month's first day. For example, a website recording USD 50,000 per month from January 1 receives January's revenue on February 1. An owner salary of USD 1,500 is gross compensation: the business pays the gross amount, the personal account receives net pay, and deductions go into a restricted tax reserve. The salary never becomes a second independent income stream.

Employee payroll is per person. A two-person group at USD 3,000 means USD 6,000 of gross wages before employer charges. Headcount is applied after individual annual contribution caps and allowances. A decrease in headcount preserves the continuing group’s per-person tax history. New hires require a separate group instead of increasing the existing group, so they do not inherit another employee’s used annual caps. Groups do not identify individual employees across separate records or employers; they are appropriate only for cohorts with the same pay and tax history.

Operating expenses reduce the business's profit. Scheduled transfers move existing money and do not reduce taxable profit. An incorporated business can deduct its owner's recorded gross salary. Sole proprietors use owner-draw transfers instead; the engine labels their personal-profit taxation as an estimate using ordinary personal income and combined social rates, without special self-employment deductions.

Legacy net-income streams remain under their old calculation until explicitly converted. Conversion starts on the selected current date and does not reconstruct historical revenue, expenses, or tax.

## Dates and settlement

Recurring amounts accrue over `[start, end)`. Partial months use actual Gregorian calendar days, including leap years. Numerators accumulate across turns and are rounded when a monthly slice settles, so splitting a time skip does not repeatedly round daily pennies. Dated amount changes, business moves, fiscal overrides, and personal tax-year boundaries produce separate slices. Each completed assessment retains its fiscal profiles and assumptions.

The coordinator settles business activity before personal bills at each month boundary. A recorded owner salary can therefore fund that month's personal bills. Replaying an already accrued interval is rejected. Opening a new business, ending an obligation, or editing a rate never deposits retroactive money.

Employee employment-age and minimum-hourly-pay checks run when a birth date and monthly hours are recorded. Missing details remain explicitly unverified; the engine does not invent either value. Owner salary requires an explicit owner tax residence. Work jurisdiction determines social charges; a separate employee tax residence can determine income tax. Cross-border calculations are estimates without treaty credits, dual-filing reconciliation, or special residency exceptions.

## Tax reserves, remittance, and annual liability

The engine computes cumulative personal income withholding and contribution caps for the earned period. This accrual convention also applies to unpaid wages. It is a disclosed simulation assumption, not a claim that every jurisdiction taxes wages when earned rather than paid. Personal payroll follows the profile's fiscal-year start; companies use an elected calendar accounting year.

Business-profit assessments preserve cumulative national brackets when moving between regions of the same country. A jurisdiction's separately modeled regional charge remains separate from a national-rate override. Annual gains use the seller's personal tax year and residence. Dated exchange assumptions convert thresholds into the life's accounting currency; moving does not convert existing balances.

Payroll deductions and funded employer/business taxes enter a restricted reserve account. They are unavailable for spending. The next monthly boundary remits those funds externally. Moving cash to a reserve and later remitting it must never charge the operating account twice. External employee payments post net wages as an expense and withholding as a balanced transfer to the reserve; owner payments are balanced transfers to the personal account and reserve.

Cumulative business losses reconcile the current year's prior assessments: cancel unpaid assessed taxes first, release excess funded reserves second, and refund only amounts already remitted. These appear as new credits or refund entries; old ledger entries and rule snapshots are never rewritten. Personal withholding and contribution calculations use incremental annual liability rather than charging the full annual tax every month.

Business-sale gains use the owner's profile. A generic VAT or sales-tax rate is not blindly applied to the sale price: the supported sale is an ownership sale. Local stamp duties, transfer levies, exemptions, fees, and treaty rules are not modeled, and the sale review explicitly labels those assumptions. The profile's transaction-tax calculator is not a complete taxable-transaction or VAT-return system.

## Insufficient funds

No automatic personal contribution, fabricated loan, or negative business balance covers a shortfall. Obligations remain in the save until paid or transferred with a sold company.

The simulation order is:

1. Due taxes and employer charges.
2. Employee payroll.
3. Operating expenses and scheduled transfers.
4. Owner salary.

Within each source account and priority, older due dates are paid first. Same-date claims share a shortfall proportionally, with deterministic minor-unit rounding. The order is a disclosed simulation policy; jurisdiction-specific insolvency proceedings, wage protections, and priority disputes are not reconstructed. Payroll deductions are reserved only in proportion to gross pay actually funded.

## Accounts and company sales

Account IDs and ledger history are permanent. Accounts may be active, closed, or transferred, with owner/manager, restricted, or no access. A restricted tax reserve cannot be spent by model proposals or manual ordinary transfers. Closing an account requires resolving its balances, accrued amounts, active recurring records, unpaid obligations, and linked financial positions. Closing the default personal account also requires an accessible replacement. Names stay unique even after closure.

A complete company sale is a proposal until the player explicitly confirms the exact saved draft. Its revision and effective date must still match the current save. The turn stops on the sale date for review; it cannot silently pass a sale mid-skip and later rewrite history. Confirmation settles activity through that date, credits the agreed price once, deducts the estimated gains tax, transfers company accounts and obligations, and ends owner compensation. The company's existing bank balance is not added to the sale proceeds. Historical company records remain readable but are excluded from player spending and management. Incoming internal transfers scheduled by another owned company end at sale; existing unpaid and pre-sale accrued transfer installments are cancelled with recorded credits, without moving cash or deleting their history. Real payroll and expense bills remain owed when their destination is transferred. They are skipped before any source debit until an explicit destination change redirects the unpaid remainder; prior partial payments remain recorded. The sale review lists the affected arrangements and this disposition.

Partial sales, retained shares or control rights, and installment sale consideration are not inferred. Explicitly selected company debt positions may be retained personally; the store validates their IDs and transfers those liabilities to the proceeds account without creating cash. Other company payables transfer with the business. A partial sale is rejected with a specific explanation. Continuing employment after a sale needs a distinct, explicit arrangement; the old owner-pay record does not continue automatically.

## Verification boundaries

Tests cover gross USD 50,000 revenue, gross USD 1,500 owner compensation, external employee net pay and balanced reserve transfers, grouped annual caps, split versus long skips, partial months, unpaid-priority settlement, reserve remittance and loss reconciliation, UK fiscal-year boundaries, account closure, sale confirmation/access, and save round trips. Store-level integration additionally verifies atomic persistence, rollback, and the compatibility of these ledger entries with existing finance invariants.

Country profiles are editable per life and carry dated sourced/estimated/non-applicable evidence. The engine does not claim exhaustive tax-return accuracy, treaty treatment, employment-law compliance, or historical verification for every nation and year. Those limitations are visible alongside the calculated records instead of being silently treated as zero or as US defaults.
