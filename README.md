# Brain Sprints Analytics

A dbt analytics engineering project modelling three raw CSV extracts; customer organisations, subscription lifecycle/payment events, and product usage events — into a tested warehouse layer and a set of business-facing marts.

The project supports analysis across the customer lifecycle:

**Acquire → Activate → Retain → Expand → Protect & Optimise Revenue**

The final marts focus on trial activation, voluntary churn signals, behavioural expansion opportunities, customer health, recurring revenue, and payment risk.

---

## Tools

- **dbt Core (1.10)** — transformation and testing framework
- **DuckDB (`dbt-duckdb`)** — local warehouse; raw CSVs are read directly using `read_csv_auto`, with no separate load step
- **MotherDuck** — used to share the built analytical warehouse

```bash
pip install dbt-duckdb

DBT_PROFILES_DIR=. dbt build

DBT_PROFILES_DIR=. dbt docs generate
```

---

## Project Structure

The project uses three modelling layers. Each layer has a distinct purpose and builds on the layer before it.

```text
models/
├── staging/
│   ├── stg_customers
│   ├── stg_subscription_events
│   └── stg_usage_events
│
├── intermediate/
│   ├── int_trial_periods
│   ├── int_trial_usage
│   ├── int_conversions
│   ├── int_churns
│   ├── int_mrr_change_events
│   └── int_latest_mrr
│
└── marts/
    ├── dim_customers
    ├── fct_subscription_events
    ├── fct_usage_events
    ├── fct_mrr_monthly
    ├── rpt_trial_activation
    ├── rpt_churn_signals
    ├── rpt_expansion_candidates
    └── rpt_customer_health
```

### Staging

One-to-one transformations of the raw source extracts.

The staging layer is responsible for:

- standardising categorical values
- cleaning whitespace and inconsistent casing
- enforcing appropriate data types
- preserving source-level fields for downstream auditability
- identifying potential duplicate usage records
- normalising financial values into a common reporting currency

### Intermediate

Reusable business-logic components that simplify downstream marts.

| Model | Purpose |
|---|---|
| `int_trial_periods` | Defines trial start and end boundaries |
| `int_trial_usage` | Aggregates product usage occurring during each trial |
| `int_conversions` | Identifies the first paid conversion event per company |
| `int_churns` | Captures relevant churn lifecycle information |
| `int_mrr_change_events` | Creates normalised MRR state-change events |
| `int_latest_mrr` | Determines the latest modelled MRR state per company |

### Marts

Business-facing dimensions, facts, and reporting models.

| Model | Purpose |
|---|---|
| `dim_customers` | One row per company containing lifecycle and current revenue state |
| `fct_subscription_events` | One row per subscription lifecycle/payment event |
| `fct_usage_events` | Deduplicated product usage events |
| `fct_mrr_monthly` | Month-end MRR, active customers, and ARPA |
| `rpt_trial_activation` | Trial engagement and conversion analysis |
| `rpt_churn_signals` | Post-conversion engagement and churn signals |
| `rpt_expansion_candidates` | Behavioural signals for potential account expansion |
| `rpt_customer_health` | Consolidated Customer Success account-health view |

Staging and intermediate models are materialised as views, while marts are materialised as tables.

The project currently contains **52 dbt tests**, including:

- uniqueness and not-null tests on primary keys
- accepted-value tests on cleaned categorical fields
- relationship tests against `stg_customers`
- singular tests for key business rules

All tests run as part of:

```bash
DBT_PROFILES_DIR=. dbt build
```

---

# Data Handling Details

## Categorical Standardisation

Inconsistent casing and whitespace were identified across fields including:

- `industry`
- `plan_name`
- `previous_plan_name`
- `usage_category`

These values are standardised in staging using a custom `title_case` macro, as DuckDB does not provide PostgreSQL's `initcap` function.

---

## Probable Duplicate Usage Events

Profiling identified **356 duplicate-looking usage events** sharing the same:

- company
- timestamp
- credit amount
- usage category
- user count

These records are flagged in `stg_usage_events` using `is_probable_duplicate` and excluded from `fct_usage_events`.

The underlying source rows are not deleted, preserving source lineage and allowing the deduplication decision to be audited.

---

## Trial-Window Boundaries

Trial usage is measured using a **calendar-day-inclusive trial window**.

The source contains date-based trial boundaries while usage events are timestamped. Both `int_trial_usage` and `rpt_trial_activation` therefore apply the same calendar-day convention to avoid excluding valid usage that occurred earlier on the recorded trial-start day.

Conceptually, the window is:

```sql
usage_at >= date_trunc('day', trial_started_at)
and usage_at < trial_end_date + interval 1 day
```

This includes the full calendar day of both the trial start and trial end.

The same boundary definition is applied consistently across the intermediate and reporting models.

---

## Currency Normalisation

The subscription dataset contains both GBP and EUR-denominated records:

- GBP: 9,040 subscription-event rows
- EUR: 82 subscription-event rows across 11 companies

Summing these values directly would incorrectly treat EUR and GBP as equivalent.

`stg_subscription_events` therefore preserves the original:

- `monthly_recurring_revenue`
- `invoice_amount`
- `currency`

and adds GBP-normalised reporting fields:

- `monthly_recurring_revenue_gbp`
- `invoice_amount_gbp`

EUR-denominated values are converted using a static dbt variable:

```yaml
eur_gbp_rate: 0.86
```

All downstream models that aggregate revenue across customers use the GBP-normalised fields, including:

- `int_conversions`
- `int_churns`
- `int_mrr_change_events`
- `int_latest_mrr`
- `fct_mrr_monthly`
- `dim_customers`

The original currency-native values remain available in `fct_subscription_events` for audit.

This is intentionally a simplified reporting approach for the exercise. A production implementation would use a date-indexed FX-rate table and convert each financial event using the appropriate point-in-time exchange rate.

---

## Monthly Recurring Revenue

`fct_mrr_monthly` reconstructs each company's MRR state at month end by replaying relevant lifecycle events, including:

- conversion
- reactivation
- upgrade
- downgrade
- churn

The model uses window functions with:

```sql
qualify row_number() over (...) = 1
```

to identify the applicable MRR state at each month end.

This avoids PostgreSQL-specific `distinct on` syntax and improves portability to warehouses such as Snowflake and BigQuery.

As of **30 June 2026**, the model produces:

- **GBP-normalised MRR:** £358,749
- **Active customers:** 635
- **ARPA:** approximately £565

---

## Current Customer State and Reactivation

Historical churn and current subscription state are treated as separate concepts.

Some customers in the dataset recorded a historical churn event and later reactivated. Therefore, the existence of a churn event does not necessarily mean that the customer is currently churned or has zero MRR.

`dim_customers` uses the source system's current `subscription_status` when determining current-state fields such as `current_mrr`.

This allows a customer to have experienced churn historically while still being correctly represented as an active, revenue-generating customer after reactivation.

Historical churn information remains available for lifecycle analysis.

---

# Key Reconciliation Figures

| Metric | Result |
|---|---:|
| Active customers | 635 |
| GBP-normalised MRR | £358,749 |
| ARPA | ~£565 |
| Ever converted | 673 of 1,000 trials |
| Trial-to-paid conversion | 67.3% |
| Currently voluntary-churned customers | 30 |
| Trial activation rate | 386 of 1,000 trials (38.6%) |

Historical churn and current churn state are reported separately. Customers that churned and subsequently reactivated remain part of historical churn analysis but are not treated as currently churned customers.

---

# Business Opportunities

The analysis is structured around the customer lifecycle:

**Acquire → Activate → Retain → Expand → Protect & Optimise Revenue**

The opportunities below represent observed patterns and commercially actionable areas identified in the data. Where the analysis shows association rather than causation, recommendations are framed as opportunities to test rather than guaranteed outcomes.

---

## 1. Improve Trial Activation to Increase Conversion — *Activate*

Trial engagement is strongly associated with conversion.

Using the corrected calendar-day trial-window logic in `rpt_trial_activation`:

- Converted customers averaged **8.9 trial usage events**, compared with **3.5** for non-converters.
- Converted customers averaged **4.4 active trial days**, compared with **2.3** for non-converters.
- Converted customers touched an average of **2.23 of 3 product categories**, compared with **1.41** for non-converters.
- Conversion rises from **31.4%** for customers with zero active trial days to **94.9%** at the highest end of trial activity.
- Customers recording **11+ trial usage events converted at 87.8%**.
- Customers meeting the activation definition — **4+ active days and all 3 product categories touched** — converted at **86.0%**, compared with **55.5%** outside the activation segment.

### Opportunity

Help more trial customers reach meaningful product activation through:

- improved onboarding
- guided first-use experiences
- inactivity-triggered nudges
- targeted intervention for trials showing low early engagement

Lower-performing acquisition channels, including self-serve, provide a useful area for targeted experimentation.

These findings demonstrate an association between activation and conversion; controlled experiments would be required to establish the causal impact of specific onboarding interventions.

---

## 2. Reduce Voluntary Churn Through Earlier Engagement Intervention — *Retain*

Voluntary churn is associated with lower sustained product engagement.

In `rpt_churn_signals`, customers currently classified as voluntary churners show:

- **54.2 average lifetime usage events**, compared with **96.6** for the rest of the converted base.
- **3.09 usage events per subscribed month**, compared with **4.59** for retained/other converted customers.

Engagement bands provide Customer Success with an observable early-warning signal for identifying accounts whose sustained product activity is declining.

Historical lifecycle analysis also shows that voluntary churn is typically preceded by a `cancellation_scheduled` event, creating an additional intervention point between demonstrated cancellation intent and final churn.

### Opportunity

Use two stages of churn intervention:

**Low sustained engagement → Early CS intervention → Cancellation scheduled → Save intervention → Churn**

Low-engagement signals can support proactive outreach before a customer decides to cancel, while a scheduled cancellation should trigger a higher-priority retention workflow during the remaining cancellation-to-churn window.

---

## 3. Build a Behavioural Expansion and Upsell Motion — *Expand*

Expansion opportunities should be identified using observable product behaviour rather than inferred seat utilisation.

Initial analysis considered comparing `seat_count_at_time` with `current_seat_count` as a capacity-utilisation measure. Validation showed that this comparison primarily captures changes in seat allocation over time rather than actual occupied-seat utilisation, so it is not used as evidence of capacity pressure.

`rpt_expansion_candidates` instead surfaces active Small and Medium customers demonstrating strong recent product engagement and consumption relative to peers on the same plan.

Signals include:

- recent usage frequency
- number of active usage days
- recent credit consumption
- credit intensity relative to the customer's plan benchmark
- previous upgrade history

### Opportunity

Provide Sales and Customer Success with a recurring behavioural expansion-candidate list, allowing teams to proactively review highly engaged accounts rather than waiting for customers to request an upgrade.

The model should be treated as a prioritisation signal rather than proof that a customer requires a larger plan.

In a production environment, actual licensed-seat and occupied-seat data would provide an additional capacity-based expansion signal.

---

## 4. Protect Revenue From Payment Failures and Delinquent Churn; *Protect & Optimise Revenue*

The subscription event data provides a lifecycle trail across:

```text
payment_failed
→ payment_recovered
→ or delinquent_churn
```

This makes payment failure an observable revenue-risk signal that can be acted on before revenue is permanently lost.

### Opportunity

Build a dedicated payment-risk and dunning workflow that:

- flags first payment failures
- identifies repeated failures
- tracks successful payment recovery
- prioritises accounts with recurring payment issues
- routes unresolved failures to Finance or Customer Success

This creates an opportunity to protect revenue that has already been acquired rather than relying exclusively on new customer growth.

---

## 5. Investigate Extreme Credit Consumption as a Revenue Opportunity and Concentration Risk; *Protect & Optimise Revenue*

Account-level product consumption is heavily right-skewed.

A small number of customers particularly on Bespoke plans account for a disproportionate share of total credit consumption.

One account, `co_0777`, is an extreme usage outlier at approximately **4.14 million lifetime credits**, substantially above the rest of the customer base.

This creates two distinct questions:

1. **Commercial opportunity:** Does the customer's Bespoke pricing appropriately reflect the level of product value and consumption?
2. **Concentration risk:** Are portfolio-level usage trends being disproportionately influenced by a single customer?

The dataset does not contain the unit cost of a credit, so high consumption alone cannot be interpreted as evidence that the customer is unprofitable.

### Opportunity

Review high-consumption Bespoke accounts jointly across Finance, Sales, and Product to understand:

- usage-driven cost-to-serve
- contract economics
- pricing structure
- renewal opportunities
- whether usage allowances or alternative packaging should be explored

Portfolio-level usage reporting should also be presented both with and without extreme outliers where appropriate, preventing a single account from obscuring underlying product-growth trends.

---

# Known Limitations and Production Improvements

This project was developed as an analytical exercise using the supplied source data. Key limitations and potential production improvements include:

- **FX conversion:** EUR values use a fixed EUR/GBP rate of `0.86`. Production reporting should use date-indexed historical FX rates.
- **Seat utilisation:** `seat_count_at_time` does not provide a reliable measure of occupied-seat utilisation. True licensed-versus-occupied-seat data would improve expansion modelling.
- **Credit economics:** Credit unit costs are unavailable, so high consumption cannot be directly translated into profitability or margin impact.
- **Activation causality:** Higher trial activation is associated with higher conversion, but experimentation would be required to establish causal impact.
- **Expansion signals:** Behavioural expansion flags are prioritisation tools for Sales/CS review, not predictions that an account will upgrade.
- **Payment monitoring:** The current project identifies payment-event patterns, but a production implementation would require operational alerting and workflow integration.
- **Floating-point aggregation:** A small number of credit aggregates may differ by approximately 0.1 at rounding boundaries due to floating-point summation order. Validation confirmed identical underlying row and category counts, and these differences do not affect the business conclusions.

---

# Validation

The final models were validated through:

- source-to-model reconciliation
- row-count comparisons
- category-level comparisons
- lifecycle edge-case testing
- trial-window boundary validation
- reactivation-state validation
- currency-normalised MRR reconciliation
- dbt schema and singular tests
