-- SQL Query to analyze Rule History and Creation Methods
-- This query shows all rule versions for a given FriendlyName regardless of creation method

-- Query 1: Get all rules for a specific FriendlyName with creation method info
DECLARE @FriendlyName VARCHAR(128) = 'YourFriendlyNameHere'; -- Replace with actual friendly name

SELECT
    r.RuleId,
    r.FriendlyName,
    r.RuleExecutionCriteriaId,
    rec.RuleExecutionCriteriaName,
    rs.RuleSetId,
    rs.RuleSetName,
    r.CreationDate,
    r.EffectiveDate,
    r.InactiveDate,
    r.UpdateDate,
    r.UpdatedBy,
    r.VerifiedDate,
    r.VerifiedBy,
    r.ProspectiveEffectiveDate,
    r.FeaturePackId,
    fp.FeaturePackName,
    rco.CreationProcessTypeId,
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod,
    rco.FriendlyName AS SourceFriendlyName,
    CASE
        WHEN r.InactiveDate IS NULL THEN 'Active'
        WHEN r.InactiveDate > GETUTCDATE() THEN 'Active'
        ELSE 'Inactive'
    END AS Status
FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
INNER JOIN RulesEngine.RuleExecutionCriteria rec ON r.RuleExecutionCriteriaId = rec.RuleExecutionCriteriaId
INNER JOIN RulesEngine.RuleSet rs ON rec.RuleSetId = rs.RuleSetId
LEFT JOIN RulesEngine.FeaturePack fp ON r.FeaturePackId = fp.FeaturePackId
WHERE r.FriendlyName = @FriendlyName
ORDER BY r.CreationDate DESC, r.RuleId DESC;

-- Query 2: Count rules by creation method for a FriendlyName
SELECT
    r.FriendlyName,
    COUNT(*) AS TotalVersions,
    SUM(CASE WHEN rco.CreationProcessTypeId = 1 THEN 1 ELSE 0 END) AS ManualCount,
    SUM(CASE WHEN rco.CreationProcessTypeId = 2 THEN 1 ELSE 0 END) AS CopyCount,
    SUM(CASE WHEN rco.CreationProcessTypeId = 3 THEN 1 ELSE 0 END) AS BulkCount,
    SUM(CASE WHEN rco.CreationProcessTypeId IS NULL THEN 1 ELSE 0 END) AS UnknownCount,
    SUM(CASE WHEN r.InactiveDate IS NULL OR r.InactiveDate > GETUTCDATE() THEN 1 ELSE 0 END) AS ActiveCount,
    SUM(CASE WHEN r.InactiveDate IS NOT NULL AND r.InactiveDate <= GETUTCDATE() THEN 1 ELSE 0 END) AS InactiveCount
FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
WHERE r.FriendlyName = @FriendlyName
GROUP BY r.FriendlyName;

-- Query 3: Find rules without RuleCreationOrigin entries
SELECT
    r.RuleId,
    r.FriendlyName,
    r.CreationDate,
    r.UpdateDate,
    r.UpdatedBy,
    'Missing RuleCreationOrigin' AS Issue
FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
WHERE r.FriendlyName = @FriendlyName
  AND rco.RuleId IS NULL;

-- Query 4: Full rule history with all details (use this for comprehensive analysis)
SELECT
    r.RuleId,
    r.FriendlyName,
    rs.RuleSetName,
    rec.RuleExecutionCriteriaName,
    r.SourceReadableStatement AS [Description],
    r.EffectiveDate,
    r.InactiveDate,
    fpvs.FunctionParameterValueSetId,
    fd.FunctionName,
    -- Extract action parameters (margin, pass-through, description)
    (SELECT et.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
       AND fp.ParameterName = 'marginPoints'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())) AS MarginPoints,
    (SELECT et.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
       AND fp.ParameterName = 'passThroughPoints'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())) AS PassThroughPoints,
    (SELECT et.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv
     INNER JOIN RulesEngine.FunctionParameter fp ON fpv.FunctionParameterId = fp.FunctionParameterId
     INNER JOIN RulesEngine.ExpressionTerm et ON fpv.ExpressionTermId = et.ExpressionTermId
     WHERE fpv.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
       AND fp.ParameterName = 'description'
       AND (fpv.InactiveDate IS NULL OR fpv.InactiveDate > GETUTCDATE())) AS ActionDescription,
    r.UpdatedBy,
    r.UpdateDate,
    CASE rco.CreationProcessTypeId
        WHEN 1 THEN 'Manual'
        WHEN 2 THEN 'Copy'
        WHEN 3 THEN 'Bulk'
        ELSE 'Unknown'
    END AS CreationMethod
FROM RulesEngine.[Rule] r
LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
INNER JOIN RulesEngine.RuleExecutionCriteria rec ON r.RuleExecutionCriteriaId = rec.RuleExecutionCriteriaId
INNER JOIN RulesEngine.RuleSet rs ON rec.RuleSetId = rs.RuleSetId
LEFT JOIN RulesEngine.FunctionParameterValueSet fpvs ON r.FunctionParameterValueSetId = fpvs.FunctionParameterValueSetId
LEFT JOIN RulesEngine.FunctionDefinition fd ON fpvs.FunctionDefinitionId = fd.FunctionDefinitionId
WHERE r.FriendlyName = @FriendlyName
ORDER BY r.CreationDate DESC, r.RuleId DESC;
