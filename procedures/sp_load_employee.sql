-- ============================================================================
-- Procedure : MULTI_AGENT_SDLC_POC.DEV.SP_LOAD_EMPLOYEE
-- Jira      : SCRUM-1 - Load only active employees and prevent duplicates
-- Purpose   : Load ACTIVE employees from the source table into EMPLOYEE_TARGET
--             while guaranteeing EMPLOYEE_ID uniqueness in the target.
--
-- Acceptance criteria implemented:
--   * Only ACTIVE employees are loaded.
--   * EMPLOYEE_ID is unique in the target.
--   * If duplicate source records exist, only one is loaded.
--   * Employees already present in the target are not inserted again.
--   * The procedure returns 'SUCCESS' after successful completion.
--
-- Assumptions (adjust to match the real schema before deployment):
--   * Source table          : MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SOURCE
--   * Target table          : MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET
--   * Key column            : EMPLOYEE_ID
--   * Active-status column   : STATUS with value 'ACTIVE'
--   * A LOAD_TS timestamp column exists on the target (defaulted here to
--     CURRENT_TIMESTAMP); remove it if the target has no such column.
--   * When multiple active source rows share an EMPLOYEE_ID, the most recent
--     one (by UPDATED_AT, then EMPLOYEE_ID) is kept.
-- ============================================================================

CREATE OR REPLACE PROCEDURE MULTI_AGENT_SDLC_POC.DEV.SP_LOAD_EMPLOYEE()
    RETURNS STRING
    LANGUAGE SQL
AS
$$
BEGIN
    -- Insert only ACTIVE, de-duplicated source rows that are not already
    -- present in the target. MERGE with a WHEN NOT MATCHED clause enforces
    -- the "no re-insert of existing employees" rule, and the de-duplicated
    -- CTE enforces the "only one row per EMPLOYEE_ID" rule.
    MERGE INTO MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET AS tgt
    USING (
        SELECT
            src.EMPLOYEE_ID,
            src.FIRST_NAME,
            src.LAST_NAME,
            src.EMAIL,
            src.DEPARTMENT,
            src.STATUS
        FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SOURCE AS src
        WHERE src.STATUS = 'ACTIVE'
        -- Keep exactly one source row per EMPLOYEE_ID (deduplicate source).
        QUALIFY ROW_NUMBER() OVER (
                    PARTITION BY src.EMPLOYEE_ID
                    ORDER BY src.UPDATED_AT DESC NULLS LAST, src.EMPLOYEE_ID
                ) = 1
    ) AS s
    ON tgt.EMPLOYEE_ID = s.EMPLOYEE_ID
    WHEN NOT MATCHED THEN
        INSERT (
            EMPLOYEE_ID,
            FIRST_NAME,
            LAST_NAME,
            EMAIL,
            DEPARTMENT,
            STATUS,
            LOAD_TS
        )
        VALUES (
            s.EMPLOYEE_ID,
            s.FIRST_NAME,
            s.LAST_NAME,
            s.EMAIL,
            s.DEPARTMENT,
            s.STATUS,
            CURRENT_TIMESTAMP()
        );

    RETURN 'SUCCESS';
END;
$$;
