/*
================================================================================
COMPLETE RULE HISTORY - MAIN UNIFIED VIEW
================================================================================
Purpose: Shows ALL changes for a given FriendlyName including:
         - Rule-level changes (UI updates)
         - Function-level changes (Bulk uploads)

This is the PRIMARY query to get complete audit trail.

Usage: Replace @FriendlyName with your rule's friendly name
Author: System Analysis
Date: December 4, 2025
================================================================================
*/

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

;WITH RuleVersionHistory AS (
    -- Part 1: Rule-level changes (UI updates, new rule versions)
    SELECT
        r.RuleId,
        r.RuleGuid,
        r.FriendlyName,
        rs.RuleSetName,
        rec.RuleExecutionCriteriaName,

        -- Change Information
        'Rule Version Change' AS ChangeType,
        r.CreationDate AS ChangeDate,
        r.UpdatedBy AS ChangedBy,
        r.UpdateDate AS UpdateDate,

        -- Status
        CASE
            WHEN r.InactiveDate IS NULL THEN 'Active'
            WHEN r.InactiveDate > GETUTCDATE() THEN 'Active (Future Inactive)'
            ELSE 'Inactive'
        END AS Status,

        r.EffectiveDate,
        r.InactiveDate,
        r.ProspectiveEffectiveDate,
        r.VerifiedDate,
        r.VerifiedBy,

        -- Function/Action Info
        fd.FunctionName,

        -- Current Action Parameter Values for this Rule Version
        (SELECT TOP 1 et.LiteralValue
         FROM RulesEngine.FunctionParameterValue fpv
         INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
         INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
         WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
           AND fp.ParameterName = 'marginPoints'
           AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())
        ) AS MarginPoints,

        (SELECT TOP 1 et.LiteralValue
         FROM RulesEngine.FunctionParameterValue fpv
         INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
         INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
         WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
           AND fp.ParameterName = 'passThroughPoints'
           AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())
        ) AS PassThroughPoints,

        (SELECT TOP 1 et.LiteralValue
         FROM RulesEngine.FunctionParameterValue fpv
         INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
         INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
         WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
           AND fp.ParameterName = 'description'
           AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())
        ) AS ActionDescription,

        -- Feature Pack
        fp.FeaturePackName,

        -- Creation Method
        CASE rco.CreationProcessTypeId
            WHEN 1 THEN 'Manual'
            WHEN 2 THEN 'Copy'
            WHEN 3 THEN 'Bulk'
            ELSE 'Unknown'
        END AS CreationMethod,

        -- Change Details (NULL for rule versions, populated for function changes)
        NULL AS ParameterChanged,
        NULL AS OldValue,
        NULL AS NewValue,

        -- For sorting and grouping
        1 AS ChangeTypeOrder -- Rule changes first

    FROM RulesEngine.[Rule] r
    LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
    INNER JOIN RulesEngine.RuleExecutionCriteria rec ON r.RuleExecutionCriteriaId = rec.RuleExecutionCriteriaId
    INNER JOIN RulesEngine.RuleSet rs ON rec.RuleSetId = rs.RuleSetId
    LEFT JOIN RulesEngine.FunctionParameterValueSet fpvs ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
    LEFT JOIN RulesEngine.FunctionDefinition fd ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId
    LEFT JOIN RulesEngine.FeaturePack fp ON r.FeaturePackId = fp.FeaturePackId
    WHERE r.FriendlyName = @FriendlyName
),

FunctionValueHistory AS (
    -- Part 2: Function-level changes (Bulk uploads)
    -- Shows changes to FunctionParameterValues for ACTIVE rules
    SELECT
        r.RuleId,
        r.RuleGuid,
        r.FriendlyName,
        rs.RuleSetName,
        rec.RuleExecutionCriteriaName,

        -- Change Information
        'Function Value Update (Bulk)' AS ChangeType,
        fpv.UpdateDate AS ChangeDate,
        fpv.UpdatedBy AS ChangedBy,
        fpv.UpdateDate AS UpdateDate,

        -- Status
        CASE
            WHEN fpv.InactiveDate IS NULL THEN 'Active'
            ELSE 'Inactive'
        END AS Status,

        fpv.EffectiveDate,
        fpv.InactiveDate,
        NULL AS ProspectiveEffectiveDate,
        NULL AS VerifiedDate,
        NULL AS VerifiedBy,

        -- Function/Action Info
        fd.FunctionName,

        -- Current values (after this change)
        CASE WHEN fp.ParameterName = 'marginPoints' THEN et.LiteralValue ELSE NULL END AS MarginPoints,
        CASE WHEN fp.ParameterName = 'passThroughPoints' THEN et.LiteralValue ELSE NULL END AS PassThroughPoints,
        CASE WHEN fp.ParameterName = 'description' THEN et.LiteralValue ELSE NULL END AS ActionDescription,

        -- Feature Pack
        fpack.FeaturePackName,

        -- Creation Method (for function changes, show what was updated)
        'Bulk Upload' AS CreationMethod,

        -- Change Details - Show which parameter was changed
        fp.ParameterName AS ParameterChanged,

        -- Get previous value (if exists)
        (SELECT TOP 1 et_prev.LiteralValue
         FROM RulesEngine.FunctionParameterValue fpv_prev
         INNER JOIN RulesEngine.ExpressionTerm et_prev ON fpv_prev.ExpressionTermId = et_prev.ExpressionTermId
         WHERE fpv_prev.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
           AND fpv_prev.FunctionParameterId = fpv.FunctionParameterId
           AND fpv_prev.UpdateDate < fpv.UpdateDate
         ORDER BY fpv_prev.UpdateDate DESC
        ) AS OldValue,

        et.LiteralValue AS NewValue,

        -- For sorting
        2 AS ChangeTypeOrder -- Function changes after rule changes

    FROM RulesEngine.[Rule] r
    INNER JOIN RulesEngine.RuleExecutionCriteria rec ON r.RuleExecutionCriteriaId = rec.RuleExecutionCriteriaId
    INNER JOIN RulesEngine.RuleSet rs ON rec.RuleSetId = rs.RuleSetId
    INNER JOIN RulesEngine.FunctionParameterValueSet fpvs ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
    INNER JOIN RulesEngine.FunctionParameterValue fpv ON fpvs.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
    INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
    INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
    LEFT JOIN RulesEngine.FunctionDefinition fd ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId
    LEFT JOIN RulesEngine.FeaturePack fpack ON r.FeaturePackId = fpack.FeaturePackId
    WHERE r.FriendlyName = @FriendlyName
      -- Only show function value changes for currently active rule
      AND r.InactiveDate IS NULL
      -- Only track key parameters that get bulk updated
      AND fp.ParameterName IN ('marginPoints', 'passThroughPoints', 'description',
                               'PassThroughRate', 'MarginMultiplier', 'Rate',
                               'NoteRateCap', 'DollarMarginTarget')
)

-- UNION the two result sets and sort chronologically
SELECT
    RuleId,
    RuleGuid,
    FriendlyName,
    RuleSetName,
    RuleExecutionCriteriaName,
    ChangeType,
    ChangeDate,
    ChangedBy,
    UpdateDate,
    Status,
    EffectiveDate,
    InactiveDate,
    ProspectiveEffectiveDate,
    VerifiedDate,
    VerifiedBy,
    FunctionName,
    MarginPoints,
    PassThroughPoints,
    ActionDescription,
    FeaturePackName,
    CreationMethod,
    ParameterChanged,
    OldValue,
    NewValue,

    -- Add helpful indicators
    CASE
        WHEN ChangeType = 'Rule Version Change' THEN
            'New rule version created' +
            CASE
                WHEN CreationMethod = 'Bulk' THEN ' via bulk upload'
                WHEN CreationMethod = 'Copy' THEN ' via copy'
                ELSE ' manually'
            END
        WHEN ChangeType = 'Function Value Update (Bulk)' THEN
            'Bulk update: ' + ParameterChanged + ' changed from ' +
            ISNULL(OldValue, 'NULL') + ' to ' + ISNULL(NewValue, 'NULL')
        ELSE 'Change recorded'
    END AS ChangeDescription

FROM (
    SELECT * FROM RuleVersionHistory
    UNION ALL
    SELECT * FROM FunctionValueHistory
) AS CompleteHistory

ORDER BY
    ChangeDate DESC,
    ChangeTypeOrder ASC, -- Show rule version changes before function changes on same date
    RuleId DESC;

GO
