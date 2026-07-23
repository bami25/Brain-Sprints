# Brain Sprints Analytics

The project supports analysis across the customer lifecycle:

**Acquire - Activate - Retain - Expand - Protect & Optimise Revenue**

The final marts focus on trial activation, voluntary churn signals, behavioural expansion opportunities, customer health, recurring revenue, and payment risk.

---

## Tools

- **dbt Core (1.10)**
- **DuckDB (`dbt-duckdb`)**
- **MotherDuck**
- **Hex**

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
