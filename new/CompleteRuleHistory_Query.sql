/*
================================================================================
COMPLETE RULE HISTORY QUERY
================================================================================
Purpose: Retrieve ALL rule versions for a given FriendlyName, regardless of
         how they were created (Manual, Copy, or Bulk upload)

Author: System Analysis
Date: December 4, 2025
================================================================================
*/

-- ============================================================================
-- MAIN QUERY: Complete Rule History
-- ============================================================================
-- This query retrieves all rule versions with full details for admin users

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    -- Primary Keys
    r.RuleId,
    r.RuleGuid,
    r.FriendlyName,

    -- Hierarchy
    rs.RuleSetId,
    rs.RuleSetName,
    rec.RuleExecutionCriteriaId,
    rec.RuleExecutionCriteriaName,
    rec.RuleExecutionCriteriaGuid,

    -- Rule Details
    r.SourceReadableStatement AS [Description],

    -- Dates
    r.CreationDate,
    r.EffectiveDate,
    r.ProspectiveEffectiveDate,
    r.InactiveDate,
    r.UpdateDate,
    r.VerifiedDate,

    -- Users
    r.UpdatedBy,
    r.VerifiedBy,

    -- Function/Action Information
    fd.FunctionDefinitionId,
    fd.FunctionName,
    fpvs.FunctionParameterValueSetId,

    -- Action Parameters - Margin Points
    (SELECT TOP 1 et.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
       AND fp.ParameterName = 'marginPoints'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())
    ) AS MarginPoints,

    -- Action Parameters - Pass Through Points
    (SELECT TOP 1 et.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
       AND fp.ParameterName = 'passThroughPoints'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())
    ) AS PassThroughPoints,

    -- Action Parameters - Description
    (SELECT TOP 1 et.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
       AND fp.ParameterName = 'description'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())
    ) AS ActionDescription,

    -- Feature Pack
    r.FeaturePackId,
    fp.FeaturePackName,

    -- Rule Group
    r.RuleGroupId,
    rg.RuleGroupName,

    -- Always Send Flag
    r.AlwaysSend,

    -- ⭐ CREATION METHOD INFORMATION ⭐
    rco.CreationProcessTypeId,
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod,
    rco.FriendlyName AS SourceFriendlyName, -- For copied rules

    -- Status
    CASE
        WHEN r.InactiveDate IS NULL THEN 'Active'
        WHEN r.InactiveDate > GETUTCDATE() THEN 'Active (Future Inactive)'
        ELSE 'Inactive'
    END AS RuleStatus,

    -- Verification Status
    CASE
        WHEN r.VerifiedDate IS NOT NULL THEN 'Verified'
        ELSE 'Unverified'
    END AS VerificationStatus,

    -- Additional Metadata
    DATEDIFF(DAY, r.CreationDate, ISNULL(r.InactiveDate, GETUTCDATE())) AS DaysActive,
    CASE WHEN r.InactiveDate IS NULL THEN 1 ELSE 0 END AS IsCurrentlyActive

FROM RulesEngine.[Rule] r

-- ⚠️ IMPORTANT: LEFT JOIN ensures we get ALL rules even if RuleCreationOrigin is missing
LEFT JOIN RulesEngine.RuleCreationOrigin rco
    ON r.RuleId = rco.RuleId

-- Required joins for hierarchy
INNER JOIN RulesEngine.RuleExecutionCriteria rec
    ON r.RuleExecutionCriteriaId = rec.RuleExecutionCriteriaId
INNER JOIN RulesEngine.RuleSet rs
    ON rec.RuleSetId = rs.RuleSetId

-- Function/Action information
LEFT JOIN RulesEngine.FunctionParameterValueSet fpvs
    ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
LEFT JOIN RulesEngine.FunctionDefinition fd
    ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId

-- Feature Pack
LEFT JOIN RulesEngine.FeaturePack fp
    ON r.FeaturePackId = fp.FeaturePackId

-- Rule Group
LEFT JOIN RulesEngine.RuleGroup rg
    ON r.RuleGroupId = rg.RuleGroupId

WHERE
    r.FriendlyName = @FriendlyName
    -- ⚠️ NO FILTER ON InactiveDate - We want ALL versions!
    -- ⚠️ NO FILTER ON CreationProcessTypeId - We want ALL creation methods!

ORDER BY
    r.CreationDate DESC,  -- Most recent first
    r.RuleId DESC;

GO

-- ============================================================================
-- SUMMARY QUERY: Rule History Statistics
-- ============================================================================
-- This provides a quick overview of rule history

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    @FriendlyName AS FriendlyName,

    -- Total Versions
    COUNT(*) AS TotalVersions,

    -- By Creation Method
    SUM(CASE WHEN rco.CreationProcessTypeId = 1 THEN 1 ELSE 0 END) AS ManualCreations,
    SUM(CASE WHEN rco.CreationProcessTypeId = 2 THEN 1 ELSE 0 END) AS CopiedVersions,
    SUM(CASE WHEN rco.CreationProcessTypeId = 3 THEN 1 ELSE 0 END) AS BulkUploaded,
    SUM(CASE WHEN rco.CreationProcessTypeId IS NULL THEN 1 ELSE 0 END) AS UnknownMethod,

    -- By Status
    SUM(CASE WHEN r.InactiveDate IS NULL THEN 1 ELSE 0 END) AS ActiveVersions,
    SUM(CASE WHEN r.InactiveDate IS NOT NULL AND r.InactiveDate <= GETUTCDATE() THEN 1 ELSE 0 END) AS InactiveVersions,
    SUM(CASE WHEN r.InactiveDate > GETUTCDATE() THEN 1 ELSE 0 END) AS FutureInactiveVersions,

    -- By Verification
    SUM(CASE WHEN r.VerifiedDate IS NOT NULL THEN 1 ELSE 0 END) AS VerifiedVersions,
    SUM(CASE WHEN r.VerifiedDate IS NULL THEN 1 ELSE 0 END) AS UnverifiedVersions,

    -- Date Range
    MIN(r.CreationDate) AS FirstCreated,
    MAX(r.CreationDate) AS LastCreated,
    DATEDIFF(DAY, MIN(r.CreationDate), MAX(r.CreationDate)) AS DaysBetweenFirstAndLast,

    -- Most Recent Active Version
    (SELECT TOP 1 r2.RuleId
     FROM RulesEngine.[Rule] r2
     WHERE r2.FriendlyName = @FriendlyName
       AND (r2.InactiveDate IS NULL OR r2.InactiveDate > GETUTCDATE())
     ORDER BY r2.CreationDate DESC) AS CurrentActiveRuleId

FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
WHERE r.FriendlyName = @FriendlyName;

GO

-- ============================================================================
-- AUDIT QUERY: Find Rules Missing RuleCreationOrigin
-- ============================================================================
-- Use this to identify data quality issues

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    r.RuleId,
    r.FriendlyName,
    r.CreationDate,
    r.UpdateDate,
    r.UpdatedBy,
    'Missing RuleCreationOrigin - Data Quality Issue' AS Issue,
    'Should be backfilled with default CreationProcessTypeId = 1 (Manual)' AS Recommendation

FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
WHERE
    r.FriendlyName = @FriendlyName
    AND rco.RuleId IS NULL;

GO

-- ============================================================================
-- COMPARISON QUERY: Compare Two Rule Versions
-- ============================================================================
-- Use this to see what changed between two specific versions

DECLARE @RuleId1 BIGINT = 0; -- ⚠️ REPLACE WITH FIRST RULE ID
DECLARE @RuleId2 BIGINT = 0; -- ⚠️ REPLACE WITH SECOND RULE ID

SELECT
    'Version 1' AS Version,
    r.RuleId,
    r.CreationDate,
    r.EffectiveDate,
    r.UpdatedBy,
    fd.FunctionName,
    (SELECT et.LiteralValue FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
       AND fp.ParameterName = 'marginPoints'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())) AS MarginPoints,
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod
FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
LEFT JOIN RulesEngine.FunctionParameterValueSet fpvs ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
LEFT JOIN RulesEngine.FunctionDefinition fd ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId
WHERE r.RuleId = @RuleId1

UNION ALL

SELECT
    'Version 2' AS Version,
    r.RuleId,
    r.CreationDate,
    r.EffectiveDate,
    r.UpdatedBy,
    fd.FunctionName,
    (SELECT et.LiteralValue FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = r.FunctionParameterValueSetId
       AND fp.ParameterName = 'marginPoints'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())) AS MarginPoints,
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod
FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
LEFT JOIN RulesEngine.FunctionParameterValueSet fpvs ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
LEFT JOIN RulesEngine.FunctionDefinition fd ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId
WHERE r.RuleId = @RuleId2;

GO

-- ============================================================================
-- TIMELINE QUERY: Rule History Timeline
-- ============================================================================
-- Shows the chronological timeline of all changes

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    r.RuleId,
    r.CreationDate AS EventDate,
    'Created' AS EventType,
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod,
    r.UpdatedBy AS PerformedBy,
    r.EffectiveDate,
    NULL AS PreviousRuleId

FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
WHERE r.FriendlyName = @FriendlyName

UNION ALL

SELECT
    r.RuleId,
    r.UpdateDate AS EventDate,
    'Updated' AS EventType,
    NULL AS CreationMethod,
    r.UpdatedBy AS PerformedBy,
    r.EffectiveDate,
    NULL AS PreviousRuleId

FROM RulesEngine.[Rule] r
WHERE r.FriendlyName = @FriendlyName
  AND r.UpdateDate IS NOT NULL

UNION ALL

SELECT
    r.RuleId,
    r.InactiveDate AS EventDate,
    'Inactivated' AS EventType,
    NULL AS CreationMethod,
    r.UpdatedBy AS PerformedBy,
    r.EffectiveDate,
    NULL AS PreviousRuleId

FROM RulesEngine.[Rule] r
WHERE r.FriendlyName = @FriendlyName
  AND r.InactiveDate IS NOT NULL

UNION ALL

SELECT
    r.RuleId,
    r.VerifiedDate AS EventDate,
    'Verified' AS EventType,
    NULL AS CreationMethod,
    r.VerifiedBy AS PerformedBy,
    r.EffectiveDate,
    NULL AS PreviousRuleId

FROM RulesEngine.[Rule] r
WHERE r.FriendlyName = @FriendlyName
  AND r.VerifiedDate IS NOT NULL

ORDER BY EventDate DESC, RuleId DESC;

GO

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 1. The main query uses LEFT JOIN for RuleCreationOrigin to ensure ALL rules
--    are returned, even if the creation origin is missing
--
-- 2. NO filters on InactiveDate - returns all versions (active and inactive)
--
-- 3. NO filters on CreationProcessTypeId - returns all creation methods
--
-- 4. The query matches the structure expected by the frontend:
--    RuleSet → RuleExecutionCriteria → Rules
--
-- 5. Action parameters are extracted using subqueries because they're stored
--    in a separate FunctionParameterValue table
--
-- 6. This query should return the EXACT same data that the API should return
--    after the fix is applied
--
-- ============================================================================
