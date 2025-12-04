/*
================================================================================
CURRENT ACTIVE RULE - FULL DETAILS
================================================================================
Purpose: Shows complete details of the CURRENTLY ACTIVE rule for a FriendlyName

This is useful for:
- Verifying what is currently in production
- Seeing current parameter values
- Understanding the latest state before making changes

Usage: Replace @FriendlyName with your rule's friendly name
Author: System Analysis
Date: December 4, 2025
================================================================================
*/

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

-- Main rule information
SELECT
    '=== CURRENT ACTIVE RULE ===' AS Section,
    r.RuleId,
    r.RuleGuid,
    r.FriendlyName,

    -- Hierarchy
    rs.RuleSetId,
    rs.RuleSetName,
    rec.RuleExecutionCriteriaId,
    rec.RuleExecutionCriteriaName,

    -- Dates
    r.CreationDate,
    r.EffectiveDate,
    r.ProspectiveEffectiveDate,
    r.InactiveDate,
    r.UpdateDate,
    r.VerifiedDate,

    -- People
    r.UpdatedBy,
    r.VerifiedBy,

    -- Function
    fd.FunctionDefinitionId,
    fd.FunctionName,

    -- Feature Pack
    fp.FeaturePackId,
    fp.FeaturePackName,

    -- Creation Origin
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod,
    rco.FriendlyName AS SourceRuleFriendlyName,

    -- Rule Group
    rg.RuleGroupId,
    rg.RuleGroupName,

    -- Status
    CASE
        WHEN r.VerifiedDate IS NOT NULL THEN 'Verified'
        ELSE 'Unverified'
    END AS VerificationStatus,

    -- Metadata
    r.SourceReadableStatement AS RuleDescription,
    r.AlwaysSend

FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
INNER JOIN RulesEngine.RuleExecutionCriteria rec ON r.RuleExecutionCriteriaId = rec.RuleExecutionCriteriaId
INNER JOIN RulesEngine.RuleSet rs ON rec.RuleSetId = rs.RuleSetId
LEFT JOIN RulesEngine.FunctionParameterValueSet fpvs ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
LEFT JOIN RulesEngine.FunctionDefinition fd ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId
LEFT JOIN RulesEngine.FeaturePack fp ON r.FeaturePackId = fp.FeaturePackId
LEFT JOIN RulesEngine.RuleGroup rg ON r.RuleGroupId = rg.RuleGroupId

WHERE r.FriendlyName = @FriendlyName
  AND (r.InactiveDate IS NULL OR r.InactiveDate > GETUTCDATE());

GO

-- Current function parameter values
DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    '=== CURRENT PARAMETER VALUES ===' AS Section,
    fp.ParameterName,
    et.LiteralValue AS CurrentValue,
    fp.DataTypeName,
    fpv.EffectiveDate,
    fpv.UpdateDate AS LastUpdated,
    fpv.UpdatedBy AS LastUpdatedBy,

    -- Show how long this value has been active
    DATEDIFF(DAY, fpv.UpdateDate, GETUTCDATE()) AS DaysSinceLastUpdate

FROM RulesEngine.[Rule] r
INNER JOIN RulesEngine.FunctionParameterValueSet fpvs
    ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
INNER JOIN RulesEngine.FunctionParameterValue fpv
    ON fpvs.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
INNER JOIN RulesEngine.FunctionParameter fp
    ON fpv.FunctionParameterId = fp.FunctionParameterId
INNER JOIN RulesEngine.ExpressionTerm et
    ON fpv.ExpressionTermId = et.ExpressionTermId

WHERE r.FriendlyName = @FriendlyName
  AND (r.InactiveDate IS NULL OR r.InactiveDate > GETUTCDATE())
  AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())

ORDER BY fp.ParameterName;

GO

-- Historical version count
DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    '=== VERSION SUMMARY ===' AS Section,
    COUNT(*) AS TotalVersions,
    SUM(CASE WHEN r.InactiveDate IS NULL OR r.InactiveDate > GETUTCDATE() THEN 1 ELSE 0 END) AS ActiveVersions,
    SUM(CASE WHEN r.InactiveDate IS NOT NULL AND r.InactiveDate <= GETUTCDATE() THEN 1 ELSE 0 END) AS InactiveVersions,
    MIN(r.CreationDate) AS FirstVersionCreated,
    MAX(r.CreationDate) AS LatestVersionCreated,
    DATEDIFF(DAY, MIN(r.CreationDate), MAX(r.CreationDate)) AS DaysBetweenFirstAndLatest

FROM RulesEngine.[Rule] r
WHERE r.FriendlyName = @FriendlyName;

GO

/*
================================================================================
SAMPLE OUTPUT:
================================================================================

=== CURRENT ACTIVE RULE ===
RuleId: 456
FriendlyName: BaseMargin_Conv30
RuleSetName: Pricing Adjustments
FunctionName: AddMargin
CreationMethod: Manual
VerificationStatus: Verified
CreationDate: 2025-11-15 09:00:00
VerifiedDate: 2025-12-01 14:20:00

=== CURRENT PARAMETER VALUES ===
ParameterName      | CurrentValue | LastUpdated         | LastUpdatedBy  | DaysSinceLastUpdate
-------------------|--------------|---------------------|----------------|--------------------
marginPoints       | 1.500        | 2025-12-04 10:30:00 | bulk.upload    | 0
passThroughPoints  | 0.625        | 2025-12-04 10:30:00 | bulk.upload    | 0
description        | Base Margin  | 2025-11-15 09:00:00 | john.doe       | 19

=== VERSION SUMMARY ===
TotalVersions: 2
ActiveVersions: 1
InactiveVersions: 1
FirstVersionCreated: 2025-10-01 08:00:00
LatestVersionCreated: 2025-11-15 09:00:00
DaysBetweenFirstAndLatest: 45

This shows:
- Current active rule is version 456, created 11/15
- Margin and passthrough were bulk updated today
- Description hasn't changed since rule creation
- There have been 2 versions total over 45 days

================================================================================
*/
