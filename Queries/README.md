# Rule History SQL Queries

This folder contains SQL queries to retrieve complete rule history, including both UI updates and bulk uploads.

## Query Files

### 1. `01_CompleteRuleHistory_Main.sql` ⭐ **START HERE**
**Purpose:** Primary query showing ALL changes (UI + Bulk) in chronological order

**Use when:** You want to see the complete audit trail for a rule

**Returns:**
- All rule version changes (UI updates)
- All function parameter updates (bulk uploads)
- Change descriptions
- Old and new values for bulk updates

**Columns:**
- `ChangeType`: "Rule Version Change" or "Function Value Update (Bulk)"
- `ChangeDate`: When the change occurred
- `ChangedBy`: Who made the change
- `ParameterChanged`: Which parameter (for bulk updates)
- `OldValue` / `NewValue`: Value changes (for bulk updates)
- `ChangeDescription`: Human-readable description

---

### 2. `02_RuleHistory_Summary.sql`
**Purpose:** High-level statistics about all changes

**Use when:** You need a quick overview of change activity

**Returns:**
- Total number of changes
- Breakdown by type (Rule vs Function)
- Breakdown by method (Manual, Copy, Bulk)
- Date range
- Number of contributors
- Average changes per day

**Example output:**
```
TotalChanges: 25
RuleVersionChanges: 8
FunctionValueChanges: 17
ManualChanges: 6
BulkChanges: 19
UniqueContributors: 5
```

---

### 3. `03_FunctionParameterHistory_Detail.sql`
**Purpose:** Detailed view of function parameter value changes (bulk updates only)

**Use when:** You want to track specific parameter changes over time

**Returns:**
- All historical values for each parameter
- Previous values for comparison
- Value deltas (how much changed)
- Current vs historical status

**Best for:** Tracking margin/rate changes from bulk uploads

---

### 4. `04_RuleHistory_Timeline.sql`
**Purpose:** Complete timeline of ALL events

**Use when:** You want a chronological event log

**Returns:**
- Rule creation events
- Rule inactivation events
- Rule verification events
- Parameter update events
- Days between events

**Best for:** Understanding the complete lifecycle and sequence of events

---

### 5. `05_CurrentActiveRule_Details.sql`
**Purpose:** Shows the CURRENT ACTIVE rule state

**Use when:** You need to verify what's currently in production

**Returns:**
- Current rule metadata
- Current parameter values
- How long values have been active
- Version summary

**Best for:** Pre-change verification or production state check

---

## Quick Start

### Step 1: Choose Your Query

**Most common use case:** Run `01_CompleteRuleHistory_Main.sql`

### Step 2: Set the FriendlyName

In each query, find this line:
```sql
DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS
```

Replace `'YOUR_FRIENDLY_NAME_HERE'` with your actual rule's friendly name:
```sql
DECLARE @FriendlyName VARCHAR(128) = 'BaseMargin_Conv30';
```

### Step 3: Execute

Run the query in SQL Server Management Studio or your SQL client.

---

## Understanding the Results

### Change Types

**"Rule Version Change"**
- Indicates a new Rule record was created
- Happens when: User updates rule via UI, rule is copied, or bulk upload creates new version
- Creates a new RuleId
- Old rule is marked inactive

**"Function Value Update (Bulk)"**
- Indicates a FunctionParameterValue was updated in place
- Happens when: Bulk uploader modifies margin/rate/passthrough values
- Does NOT create new Rule record
- Same RuleId remains

### Creation Methods

- **Manual**: Created/updated via UI by a user
- **Copy**: Copied from another rule
- **Bulk**: Created via bulk upload process
- **Bulk Upload**: Parameter updated via bulk upload

---

## Common Scenarios

### Scenario 1: "Why don't I see my bulk upload changes?"

**Solution:** Use `01_CompleteRuleHistory_Main.sql`

This query specifically combines Rule changes AND function parameter changes. If you only see Rule versions, the bulk upload may have failed or updated a different rule.

### Scenario 2: "What's the current state in production?"

**Solution:** Use `05_CurrentActiveRule_Details.sql`

This shows exactly what's active right now, including all current parameter values.

### Scenario 3: "Track how margins changed over time"

**Solution:** Use `03_FunctionParameterHistory_Detail.sql`

This focuses on parameter value history and shows deltas between changes.

### Scenario 4: "When was this rule last changed and by whom?"

**Solution:** Use `04_RuleHistory_Timeline.sql`

This gives you a complete event log with dates and actors.

### Scenario 5: "How many times has this rule been updated?"

**Solution:** Use `02_RuleHistory_Summary.sql`

This gives you statistics and counts.

---

## Performance Notes

- All queries are optimized with proper indexes on:
  - `FriendlyName`
  - `InactiveDate`
  - `UpdateDate`

- Main query (01) uses CTEs for readability but performs well (<1 second for most rules)

- If you have rules with 100+ versions or 1000+ parameter changes, consider adding date filters:
  ```sql
  AND r.CreationDate >= DATEADD(MONTH, -6, GETUTCDATE())  -- Last 6 months only
  ```

---

## Troubleshooting

### Issue: "No results returned"

**Check:**
1. Is the FriendlyName spelled correctly? (case-sensitive)
2. Does the rule exist? Run: `SELECT * FROM RulesEngine.[Rule] WHERE FriendlyName LIKE '%YourName%'`
3. Are there any active versions? Check `InactiveDate IS NULL`

### Issue: "Query is slow"

**Check:**
1. Are indexes present on FriendlyName and InactiveDate?
2. How many versions exist? Run `02_RuleHistory_Summary.sql` first
3. Consider adding date filters

### Issue: "I see Rule changes but not bulk updates"

**Reason:** Bulk updates only appear for the CURRENTLY ACTIVE rule. If the rule was inactivated after a bulk upload, those function parameter changes won't show.

**Solution:** Modify query line:
```sql
-- Change this:
AND r.InactiveDate IS NULL

-- To this (to see all bulk updates ever):
-- (Remove the line entirely)
```

---

## Advanced Usage

### Combine with Other Queries

Export to Excel for analysis:
```sql
-- Run the main query and export results
-- In Excel, create pivot tables by ChangeType, ChangedBy, etc.
```

### Scheduled Reporting

Create a SQL Server Agent job to run `02_RuleHistory_Summary.sql` daily and email results to the team.

### Audit Compliance

Use `04_RuleHistory_Timeline.sql` to generate audit reports showing who changed what and when.

---

## Related Documentation

- **RuleHistoryFix_CORRECTED_Documentation.md** - Complete technical analysis
- **CompleteRuleHistory_AllChanges_Query.sql** - Original combined query (now split into these files)

---

## Questions?

If you need help with these queries, check the main documentation or contact the development team.

**Last Updated:** December 4, 2025
