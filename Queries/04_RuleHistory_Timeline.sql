/*
================================================================================
RULE HISTORY - CHRONOLOGICAL TIMELINE
================================================================================
Purpose: Shows a complete timeline of all events for a rule

Events include:
- Rule creation
- Rule inactivation
- Rule verification
- Function parameter updates (bulk)

This gives a complete audit log of the rule's lifecycle.

Usage: Replace @FriendlyName with your rule's friendly name
Author: System Analysis
Date: December 4, 2025
================================================================================
*/

DECLARE @FriendlyName VARCHAR(128) = 'YOUR_FRIENDLY_NAME_HERE'; -- ⚠️ REPLACE THIS

;WITH AllEvents AS (
    -- Rule creation events
    SELECT
        r.RuleId,
        r.CreationDate AS EventTimestamp,
        'Rule Created' AS EventType,
        r.UpdatedBy AS Actor,
        CASE rco.CreationProcessTypeId
            WHEN 1 THEN 'Manual'
            WHEN 2 THEN 'Copy'
            WHEN 3 THEN 'Bulk'
            ELSE 'Unknown'
        END AS Method,
        'RuleId: ' + CAST(r.RuleId AS VARCHAR) AS Details,
        1 AS EventPriority
    FROM RulesEngine.[Rule] r
    LEFT JOIN RulesEngine.RuleCreationOrigin rco ON r.RuleId = rco.RuleId
    WHERE r.FriendlyName = @FriendlyName

    UNION ALL

    -- Rule inactivation events
    SELECT
        r.RuleId,
        r.InactiveDate AS EventTimestamp,
        'Rule Inactivated' AS EventType,
        r.UpdatedBy AS Actor,
        NULL AS Method,
        'RuleId: ' + CAST(r.RuleId AS VARCHAR) + ' marked inactive' AS Details,
        2 AS EventPriority
    FROM RulesEngine.[Rule] r
    WHERE r.FriendlyName = @FriendlyName
      AND r.InactiveDate IS NOT NULL

    UNION ALL

    -- Rule verification events
    SELECT
        r.RuleId,
        r.VerifiedDate AS EventTimestamp,
        'Rule Verified' AS EventType,
        r.VerifiedBy AS Actor,
        NULL AS Method,
        'RuleId: ' + CAST(r.RuleId AS VARCHAR) + ' verified' AS Details,
        3 AS EventPriority
    FROM RulesEngine.[Rule] r
    WHERE r.FriendlyName = @FriendlyName
      AND r.VerifiedDate IS NOT NULL

    UNION ALL

    -- Function parameter updates (bulk uploads)
    SELECT
        r.RuleId,
        fpv.UpdateDate AS EventTimestamp,
        'Parameter Updated' AS EventType,
        fpv.UpdatedBy AS Actor,
        'Bulk Upload' AS Method,
        fp.ParameterName + ' changed to: ' + et.LiteralValue AS Details,
        4 AS EventPriority
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
      AND r.InactiveDate IS NULL
      AND fp.ParameterName IN ('marginPoints', 'passThroughPoints', 'description')
)

SELECT
    EventTimestamp,
    EventType,
    Actor,
    Method,
    Details,
    RuleId,

    -- Add relative time indicators
    DATEDIFF(DAY, LAG(EventTimestamp) OVER (ORDER BY EventTimestamp), EventTimestamp) AS DaysSincePreviousEvent,

    -- Add helpful formatting
    CASE
        WHEN EventType = 'Rule Created' THEN '🆕'
        WHEN EventType = 'Rule Inactivated' THEN '⛔'
        WHEN EventType = 'Rule Verified' THEN '✓'
        WHEN EventType = 'Parameter Updated' THEN '📝'
        ELSE ''
    END AS Icon

FROM AllEvents
WHERE EventTimestamp IS NOT NULL
ORDER BY EventTimestamp DESC, EventPriority ASC;

GO

/*
================================================================================
SAMPLE OUTPUT:
================================================================================

EventTimestamp       | EventType          | Actor        | Method      | Details                                | DaysSincePreviousEvent
---------------------|--------------------|--------------| ------------|----------------------------------------|------------------------
2025-12-04 10:30:00  | Parameter Updated  | bulk.upload  | Bulk Upload | marginPoints changed to: 1.500         | 0
2025-12-04 10:30:00  | Parameter Updated  | bulk.upload  | Bulk Upload | passThroughPoints changed to: 0.625    | 0
2025-12-01 14:20:00  | Rule Verified      | jane.smith   | NULL        | RuleId: 456 verified                   | 3
2025-11-15 09:00:00  | Rule Created       | john.doe     | Manual      | RuleId: 456                            | 16
2025-11-15 09:00:00  | Rule Inactivated   | john.doe     | NULL        | RuleId: 123 marked inactive            | 0
2025-10-30 16:45:00  | Parameter Updated  | bulk.upload  | Bulk Upload | marginPoints changed to: 1.250         | 16
2025-10-01 08:00:00  | Rule Created       | john.doe     | Manual      | RuleId: 123                            | 29

This timeline shows:
- Rule 123 was created on 10/01
- Bulk update on 10/30 (29 days later)
- New version (Rule 456) created on 11/15, old rule inactivated
- Rule verified on 12/01
- Another bulk update on 12/04 (same day, multiple parameters)

================================================================================
*/
