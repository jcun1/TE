/*
================================================================================
RULE HISTORY - SUMMARY STATISTICS
================================================================================
Purpose: Provides high-level statistics about all changes to a rule

Shows:
- Total number of changes
- Breakdown by type (Rule versions vs Function updates)
- Breakdown by method (Manual, Copy, Bulk)
- Date range
- Number of unique contributors

Usage: Replace @FriendlyName with your rule's friendly name
Author: System Analysis
Date: December 4, 2025
================================================================================
*/

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

;WITH AllChanges AS (
    -- Rule version changes
    SELECT
        'Rule Version' AS ChangeCategory,
        r.CreationDate AS ChangeDate,
        r.UpdatedBy AS ChangedBy,
        CASE rco.CreationProcessTypeId
            WHEN 1 THEN 'Manual'
            WHEN 2 THEN 'Copy'
            WHEN 3 THEN 'Bulk'
            ELSE 'Unknown'
        END AS Method
    FROM RulesEngine.[Rule] r
    LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
    WHERE r.FriendlyName = @FriendlyName

    UNION ALL

    -- Function value changes (for currently active rule)
    SELECT
        'Function Value' AS ChangeCategory,
        fpv.UpdateDate AS ChangeDate,
        fpv.UpdatedBy AS ChangedBy,
        'Bulk Upload' AS Method
    FROM RulesEngine.[Rule] r
    INNER JOIN RulesEngine.FunctionParameterValueSet fpvs
        ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
    INNER JOIN RulesEngine.FunctionParameterValue fpv
        ON fpvs.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
    INNER JOIN RulesEngine.FunctionParameter fp
        ON fpv.FunctionParameterId = fp.FunctionParameterId
    WHERE r.FriendlyName = @FriendlyName
      AND r.InactiveDate IS NULL
      AND fp.ParameterName IN ('marginPoints', 'passThroughPoints', 'description',
                               'PassThroughRate', 'MarginMultiplier', 'Rate',
                               'NoteRateCap', 'DollarMarginTarget')
)

SELECT
    @FriendlyName AS FriendlyName,

    -- Total changes
    COUNT(*) AS TotalChanges,

    -- By category
    SUM(CASE WHEN ChangeCategory = 'Rule Version' THEN 1 ELSE 0 END) AS RuleVersionChanges,
    SUM(CASE WHEN ChangeCategory = 'Function Value' THEN 1 ELSE 0 END) AS FunctionValueChanges,

    -- By method
    SUM(CASE WHEN Method = 'Manual' THEN 1 ELSE 0 END) AS ManualChanges,
    SUM(CASE WHEN Method = 'Copy' THEN 1 ELSE 0 END) AS CopyChanges,
    SUM(CASE WHEN Method = 'Bulk' OR Method = 'Bulk Upload' THEN 1 ELSE 0 END) AS BulkChanges,

    -- Date range
    MIN(ChangeDate) AS FirstChange,
    MAX(ChangeDate) AS LastChange,
    DATEDIFF(DAY, MIN(ChangeDate), MAX(ChangeDate)) AS DaysBetweenFirstAndLast,

    -- Unique contributors
    COUNT(DISTINCT ChangedBy) AS UniqueContributors,

    -- Additional metrics
    CAST(COUNT(*) AS FLOAT) / NULLIF(DATEDIFF(DAY, MIN(ChangeDate), MAX(ChangeDate)), 0) AS AvgChangesPerDay

FROM AllChanges;

GO

/*
================================================================================
SAMPLE OUTPUT:
================================================================================

FriendlyName         | TotalChanges | RuleVersionChanges | FunctionValueChanges | ManualChanges | BulkChanges
---------------------|--------------|--------------------|--------------------- |---------------|-------------
BaseMargin_Conv30    | 25           | 8                  | 17                   | 6             | 19

FirstChange          | LastChange           | DaysBetweenFirstAndLast | UniqueContributors
---------------------|----------------------|-------------------------|-------------------
2024-01-15 10:00:00  | 2025-12-04 14:30:00  | 324                     | 5

This tells you:
- 25 total changes to this rule
- 8 were new rule versions (UI updates)
- 17 were bulk parameter updates
- Average of 0.077 changes per day
- 5 different people have modified this rule

================================================================================
*/
