# Rule History Screen - Display All Versions Regardless of Update Method

## CORRECTED ANALYSIS

**Date:** December 4, 2025
**Status:** Root Cause Identified - Architecture Issue

---

## Critical Discovery

**The original analysis was incorrect.** The issue is NOT a missing `.Include()` statement.

### The Real Problem

**Rule updates made via the UI:**
- Updates are saved at the **Rule level**
- Creates new Rule records with new `RuleId`
- Old rules are marked inactive (`InactiveDate` set)
- New rule gets new `CreationDate`
- **Result:** Appears in Rule History Screen ✓

**Rule updates made via Bulk Uploader:**
- Updates are saved at the **FunctionParameterValue level** (function-level changes)
- Does NOT create new Rule records
- Does NOT change `RuleId`
- Does NOT update `Rule.UpdateDate` or `Rule.UpdatedBy`
- Only updates `FunctionParameterValue` records (margin points, passthrough points, etc.)
- **Result:** Does NOT appear in Rule History Screen ✗

---

## Architecture Deep Dive

### Database Structure

```
Rule (Main rule entity)
├── RuleId (PK)
├── FriendlyName (groups versions)
├── CreationDate
├── UpdateDate
├── InactiveDate (NULL = active)
├── FunctionParameterValueSetId (FK) → FunctionParameterValueSet
│
└── FunctionParameterValueSet
    ├── FunctionParameterValueSetId (PK)
    ├── FunctionDefinitionId (FK)
    └── Contains multiple FunctionParameterValue records
        │
        └── FunctionParameterValue (This is where bulk updates happen!)
            ├── FunctionParameterValueId (PK)
            ├── FunctionParameterValueSetId (FK)
            ├── FunctionParameterId (FK) → FunctionParameter
            ├── ExpressionTermId (FK) → ExpressionTerm
            ├── UpdateDate ← BULK UPLOADER UPDATES THIS
            ├── UpdatedBy ← BULK UPLOADER UPDATES THIS
            └── InactiveDate

            ExpressionTerm
            ├── ExpressionTermId (PK)
            └── LiteralValue ← THE ACTUAL VALUE (margin, passthrough, etc.)
```

### How Updates Work

#### UI Updates (Manual):
```csharp
// File: RulesEngineManager.cs - UpdateRuleAsync()
1. Load existing Rule by RuleId
2. Set existing Rule.InactiveDate = NOW (deactivate old version)
3. Create NEW Rule record with:
   - New RuleId (auto-increment)
   - Same FriendlyName
   - New CreationDate = NOW
   - New FunctionParameterValueSet (deep copy)
   - UpdatedBy = current user
4. Result: Two Rule records with same FriendlyName
   - Old: RuleId=123, InactiveDate=NOW
   - New: RuleId=456, InactiveDate=NULL
```

#### Bulk Uploader Updates:
```csharp
// File: RulesEngineManager.cs - ImportAdjustmentValuesAsync()
// Line 517-522
await UpdateActionValuesForParameter(worksheetDataTable, friendlyNameColumnHeader,
    username, "PassThroughPoints", "PassThrough Points", results);
await UpdateActionValuesForParameter(worksheetDataTable, friendlyNameColumnHeader,
    username, "MarginPoints", "Margin Points", results);

// This calls stored procedure: RulesEngine.usp_UpdateActionValuesForParam
// Which does:
1. Find Rules by FriendlyName WHERE InactiveDate IS NULL (active rules only)
2. For each rule's FunctionParameterValueSet:
   a. Set existing FunctionParameterValue.InactiveDate = NOW
   b. Create NEW FunctionParameterValue with:
      - New FunctionParameterValueId
      - New ExpressionTermId
      - New LiteralValue (the updated margin/passthrough value)
      - UpdateDate = NOW
      - UpdatedBy = username
3. Result:
   - SAME Rule record (RuleId unchanged!)
   - New FunctionParameterValue records
   - Rule.UpdateDate NOT changed
   - Rule.UpdatedBy NOT changed
```

---

## Why Rule History Doesn't Show Bulk Updates

The Rule History screen queries by `FriendlyName` and displays all Rule records:

```csharp
// RulesEngineManager.cs - GetRuleHistoryAsync()
var rules = await dao.GetRulesAsync(
    x => x.FriendlyName == friendlyName,
    includeInactive: true  // Gets ALL rule versions
);
```

**Problem:**
- Bulk updates don't create new Rule records
- They only create new FunctionParameterValue records
- `GetRulesAsync` returns Rule entities, not FunctionParameterValue entities
- Therefore, bulk updates are invisible to the history query

---

## The Real Solution

To display bulk uploader changes in Rule History, you need to:

### Option 1: Change Bulk Uploader to Create New Rule Versions (Recommended)

**Modify:** `RulesEngineManager.ImportAdjustmentValuesAsync()`

Instead of updating `FunctionParameterValue` in-place, create new Rule versions:

```csharp
// Pseudocode for new approach:
foreach (var friendlyName in updatedRules)
{
    var existingRule = await GetActiveRuleByFriendlyName(friendlyName);

    // Deactivate old rule
    existingRule.InactiveDate = DateTime.UtcNow;
    existingRule.UpdateDate = DateTime.UtcNow;
    existingRule.UpdatedBy = username;
    await UpdateRuleAsync(existingRule);

    // Create new rule version with updated values
    var newRule = DeepClone(existingRule);
    newRule.RuleId = 0; // Let DB assign new ID
    newRule.InactiveDate = null;
    newRule.CreationDate = DateTime.UtcNow;
    newRule.UpdateDate = DateTime.UtcNow;
    newRule.UpdatedBy = username;
    newRule.RuleCreationOrigin = new RuleCreationOrigin
    {
        CreationProcessType = CreationProcessType.Bulk
    };

    // Update the function parameter values in the cloned structure
    UpdateFunctionParameterValues(newRule, newValues);

    await CreateRuleAsync(newRule, username);
}
```

**Pros:**
- Consistent with UI behavior
- Full audit trail at Rule level
- Works with existing Rule History screen
- No UI changes needed

**Cons:**
- More database records (one Rule per bulk update)
- More complex bulk update logic
- Potential performance impact for large bulk updates

---

### Option 2: Enhance History Screen to Show Function-Level Changes (Complex)

**Modify:** Rule History screen to also query `FunctionParameterValue` history

**Changes Required:**

1. **Backend - New Method:**
```csharp
// IRulesEngineManager.cs
Task<IList<RuleHistoryItem>> GetCompleteRuleHistoryAsync(string friendlyName);

// Returns combined history of:
// - Rule-level changes (current behavior)
// - Function-level changes (bulk updates)
```

2. **Backend - New Query:**
```csharp
// Get all Rule versions
var ruleVersions = await GetRulesAsync(x => x.FriendlyName == friendlyName, true);

// Get all FunctionParameterValue changes for this FriendlyName
var functionChanges = await GetFunctionParameterValueHistoryAsync(friendlyName);

// Merge and return as unified timeline
return MergeHistoryItems(ruleVersions, functionChanges);
```

3. **Frontend - Update Component:**
```typescript
// Add indicator for change type
displayedRuleColumns = [
  'changeType',  // NEW: "Rule Update" vs "Value Update"
  'actions',
  'ruleSetName',
  // ... existing columns
];
```

**Pros:**
- Shows complete history including bulk updates
- Doesn't change bulk uploader behavior
- More granular audit trail

**Cons:**
- Complex query logic (merge two different entity types)
- UI changes required
- Performance concerns (querying FunctionParameterValue history)
- Difficult to reconstruct "what the rule looked like" at a point in time

---

### Option 3: Hybrid Approach (Recommended Alternative)

**Keep both mechanisms but add visibility:**

1. **Keep bulk uploader as-is** (updates function values in place)
2. **Add audit table** to track bulk update events
3. **Enhance history screen** to show both rule versions AND bulk update events

**New Table:**
```sql
CREATE TABLE [RulesEngine].[BulkUpdateAudit](
    [BulkUpdateAuditId] [bigint] IDENTITY(1,1) NOT NULL,
    [FriendlyName] [varchar](128) NOT NULL,
    [RuleId] [bigint] NOT NULL,  -- Rule that was updated
    [ParameterName] [varchar](50) NOT NULL,  -- marginPoints, passThroughPoints, etc.
    [OldValue] [varchar](800) NULL,
    [NewValue] [varchar](800) NULL,
    [UpdateDate] [datetime] NOT NULL,
    [UpdatedBy] [varchar](62) NOT NULL,
    [UploadFileName] [varchar](255) NULL,
    PRIMARY KEY ([BulkUpdateAuditId])
);
```

**Modified Bulk Uploader:**
```csharp
// In UpdateActionValuesForParameter:
// After updating FunctionParameterValue:
await LogBulkUpdateAudit(friendlyName, ruleId, paramName, oldValue, newValue, username, fileName);
```

**Enhanced History Query:**
```csharp
// Return combined results:
// 1. Rule versions (existing)
// 2. Bulk update audit entries
return ruleVersions.Union(bulkUpdateEvents).OrderByDescending(x => x.Date);
```

**Pros:**
- Minimal changes to bulk uploader
- Preserves current performance
- Full audit trail
- Can show detailed value changes

**Cons:**
- New table and audit logic
- UI needs to handle mixed record types

---

## SQL Query to See Current State

### Find Rules and Their Function Value Changes

```sql
-- Show all Rule versions
SELECT
    r.RuleId,
    r.FriendlyName,
    r.CreationDate AS RuleCreationDate,
    r.UpdateDate AS RuleUpdateDate,
    r.UpdatedBy AS RuleUpdatedBy,
    r.InactiveDate AS RuleInactiveDate,
    'Rule Version Change' AS ChangeType
FROM RulesEngine.[Rule] r
WHERE r.FriendlyName = 'YOUR_FRIENDLY_NAME'

UNION ALL

-- Show all FunctionParameterValue changes
SELECT
    r.RuleId,
    r.FriendlyName,
    fpv.CreationDate AS ValueCreationDate,
    fpv.UpdateDate AS ValueUpdateDate,
    fpv.UpdatedBy AS ValueUpdatedBy,
    fpv.InactiveDate AS ValueInactiveDate,
    'Function Value Change (Bulk Update)' AS ChangeType
FROM RulesEngine.[Rule] r
INNER JOIN RulesEngine.FunctionParameterValueSet fpvs
    ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
INNER JOIN RulesEngine.FunctionParameterValue fpv
    ON fpvs.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
WHERE r.FriendlyName = 'YOUR_FRIENDLY_NAME'
  AND r.InactiveDate IS NULL  -- Current active rule

ORDER BY 3 DESC;  -- Order by creation date
```

### Compare Function Values Over Time

```sql
-- Show how margin points changed over time for a rule
SELECT
    r.RuleId,
    r.FriendlyName,
    fp.ParameterName,
    et.LiteralValue AS Value,
    fpv.EffectiveDate,
    fpv.InactiveDate,
    fpv.UpdateDate,
    fpv.UpdatedBy,
    CASE
        WHEN fpv.InactiveDate IS NULL THEN 'Current'
        ELSE 'Historical'
    END AS Status
FROM RulesEngine.[Rule] r
INNER JOIN RulesEngine.FunctionParameterValueSet fpvs
    ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
INNER JOIN RulesEngine.FunctionParameterValue fpv
    ON fpvs.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
INNER JOIN RulesEngine.FunctionParameter fp
    ON fpv.FunctionParameterId = fp.FunctionParameterId
INNER JOIN RulesEngine.ExpressionTerm et
    ON fpv.ExpressionTermId = et.ExpressionTermId
WHERE r.FriendlyName = 'YOUR_FRIENDLY_NAME'
  AND r.InactiveDate IS NULL  -- Current active rule
  AND fp.ParameterName IN ('marginPoints', 'passThroughPoints')
ORDER BY fp.ParameterName, fpv.UpdateDate DESC;
```

---

## Recommended Implementation Plan

### Phase 1: Immediate (Quick Win)
**Implement Option 3 - Hybrid Approach**

1. Create `BulkUpdateAudit` table
2. Modify `UpdateActionValuesForParameter` to log changes
3. Create new API endpoint: `GET /api/v1/core/rulesengine/rule/completehistory?friendlyName={name}`
4. Update frontend to show both types of changes

**Effort:** 2-3 days
**Impact:** Full visibility into all changes
**Risk:** Low (additive changes only)

---

### Phase 2: Long-term (Architectural Fix)
**Implement Option 1 - Standardize on Rule Versioning**

1. Refactor bulk uploader to create new Rule versions
2. Deprecate in-place FunctionParameterValue updates
3. Add bulk upload indicator in RuleCreationOrigin
4. Update documentation

**Effort:** 1-2 weeks
**Impact:** Consistent versioning model
**Risk:** Medium (changes existing behavior)

---

## Files to Modify

### Option 3 (Recommended):

**Database:**
- Create migration for `BulkUpdateAudit` table

**Backend:**
- `LD.PPE.Core.Persistance/RulesEngine/RuleEngineDAO.cs`
  - Add `LogBulkUpdateAuditAsync()`
  - Add `GetBulkUpdateAuditAsync()`
- `LD.PPE.Core.Logic/RulesEngine/RulesEngineManager.cs`
  - Modify `UpdateActionValuesForParameter()` line 760
  - Add `GetCompleteRuleHistoryAsync()`
- `LD.PPE.Core.Service/Controllers/RulesEngineController.cs`
  - Add `GetCompleteRuleHistory()` endpoint

**Frontend:**
- `src/app/modules/routing/pages/rule-history/rule-history.component.ts`
  - Update to call new endpoint
  - Handle mixed record types
- `src/app/modules/routing/pages/rule-history/rule-history.component.html`
  - Add change type column
  - Show value delta for bulk updates

---

## Testing Scenarios

### Verify Current Behavior

1. **Manual Update:**
   - Update a rule via UI
   - Check: New Rule record created? ✓
   - Check: Appears in history? ✓

2. **Bulk Update:**
   - Update same rule via bulk uploader
   - Check: New Rule record created? ✗ (This is the problem!)
   - Check: Appears in history? ✗ (This is the symptom!)
   - Check: New FunctionParameterValue records? ✓
   - Check: Rule.UpdateDate changed? ✗

### After Fix (Option 3)

1. **History shows both:**
   - Rule version changes (rows with "Rule Update")
   - Bulk updates (rows with "Bulk Update: marginPoints changed")

2. **Bulk update entry shows:**
   - Date/time of bulk upload
   - User who uploaded
   - Parameter that changed (marginPoints, etc.)
   - Old value → New value
   - Rule that was affected

---

## Summary

**Original Problem:** Bulk uploaded rules don't appear in history

**Root Cause:** Bulk uploader updates FunctionParameterValue records, not Rule records. History screen only shows Rule records.

**Solution:** Either make bulk uploader create Rule versions (Option 1) OR enhance history to show function-level changes (Option 3).

**Recommended:** Option 3 (Hybrid) for quick implementation, followed by Option 1 for long-term consistency.

---

**END OF CORRECTED DOCUMENTATION**
