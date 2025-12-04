/*
================================================================================
FUNCTION PARAMETER VALUE HISTORY - DETAILED
================================================================================
Purpose: Shows detailed history of function parameter value changes (bulk updates)

This query focuses ONLY on bulk upload changes and shows:
- Which parameters were changed
- Old and new values
- Value deltas (for numeric parameters)
- Who made the change and when

Usage: Replace @FriendlyName with your rule's friendly name
Author: System Analysis
Date: December 4, 2025
================================================================================
*/

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

SELECT
    r.RuleId,
    r.FriendlyName,
    fp.ParameterName,
    et.LiteralValue AS CurrentValue,
    fpv.EffectiveDate,
    fpv.InactiveDate,
    fpv.CreationDate AS ValueCreationDate,
    fpv.UpdateDate AS ValueUpdateDate,
    fpv.UpdatedBy,

    -- Show if this is the current active value
    CASE
        WHEN fpv.InactiveDate IS NULL THEN 'Current Active Value'
        WHEN fpv.InactiveDate > GETUTCDATE() THEN 'Active (Future Inactive)'
        ELSE 'Historical Value'
    END AS ValueStatus,

    -- Get the previous value for comparison
    (SELECT TOP 1 et_prev.LiteralValue
     FROM RulesEngine.FunctionParameterValue fpv_prev
     INNER JOIN RulesEngine.ExpressionTerm et_prev
         ON fpv_prev.ExpressionTermId = et_prev.ExpressionTermId
     WHERE fpv_prev.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
       AND fpv_prev.FunctionParameterId = fpv.FunctionParameterId
       AND fpv_prev.UpdateDate < fpv.UpdateDate
     ORDER BY fpv_prev.UpdateDate DESC
    ) AS PreviousValue,

    -- Calculate the delta for numeric parameters
    CASE
        WHEN fp.ParameterName LIKE '%Points'
          OR fp.ParameterName LIKE '%Rate'
          OR fp.ParameterName LIKE '%Multiplier' THEN
            TRY_CAST(et.LiteralValue AS DECIMAL(10,3)) -
            TRY_CAST((SELECT TOP 1 et_prev.LiteralValue
                      FROM RulesEngine.FunctionParameterValue fpv_prev
                      INNER JOIN RulesEngine.ExpressionTerm et_prev
                          ON fpv_prev.ExpressionTermId = et_prev.ExpressionTermId
                      WHERE fpv_prev.FunctionParameterValueSetId = fpv.FunctionParameterValueSetId
                        AND fpv_prev.FunctionParameterId = fpv.FunctionParameterId
                        AND fpv_prev.UpdateDate < fpv.UpdateDate
                      ORDER BY fpv_prev.UpdateDate DESC) AS DECIMAL(10,3))
        ELSE NULL
    END AS ValueDelta,

    -- Add change indicator
    CASE
        WHEN fpv.InactiveDate IS NULL THEN '← CURRENT'
        ELSE ''
    END AS Indicator

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
  AND r.InactiveDate IS NULL -- Only current active rule
  AND fp.ParameterName IN ('marginPoints', 'passThroughPoints', 'description',
                           'PassThroughRate', 'MarginMultiplier', 'Rate',
                           'NoteRateCap', 'DollarMarginTarget')

ORDER BY
    fp.ParameterName,
    fpv.UpdateDate DESC;

GO

/*
================================================================================
SAMPLE OUTPUT:
================================================================================

ParameterName    | CurrentValue | PreviousValue | ValueDelta | ValueUpdateDate     | UpdatedBy      | ValueStatus
-----------------|--------------|---------------|------------|---------------------|----------------|------------------
marginPoints     | 1.500        | 1.250         | +0.250     | 2025-12-01 10:30:00 | bulk.upload    | Current Active ←
marginPoints     | 1.250        | 1.000         | +0.250     | 2025-11-10 09:15:00 | bulk.upload    | Historical
marginPoints     | 1.000        | NULL          | NULL       | 2025-10-01 08:00:00 | john.doe       | Historical
passThroughPoints| 0.625        | 0.500         | +0.125     | 2025-12-01 10:30:00 | bulk.upload    | Current Active ←
passThroughPoints| 0.500        | NULL          | NULL       | 2025-10-01 08:00:00 | john.doe       | Historical

This shows:
- marginPoints was increased from 1.000 → 1.250 → 1.500 over 3 updates
- passThroughPoints was increased from 0.500 → 0.625
- All bulk uploads happened on the same date (2025-12-01)
- Original values were set manually by john.doe

================================================================================
*/
