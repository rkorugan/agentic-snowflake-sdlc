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
-- Live schema columns (verified via INFORMATION_SCHEMA):
--   EMPLOYEE_SOURCE : EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT,
--                     EMPLOYEE_STATUS, SALARY, UPDATED_TS
--   EMPLOYEE_TARGET : EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT,
--                     EMPLOYEE_STATUS, SALARY, LOAD_TS
-- ============================================================================

CREATE OR REPLACE PROCEDURE MULTI_AGENT_SDLC_POC.DEV.SP_LOAD_EMPLOYEE()
    RETURNS STRING
    LANGUAGE SQL
AS
$$
BEGIN
    MERGE INTO MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET AS tgt
    USING (
        SELECT
            src.EMPLOYEE_ID,
            src.EMPLOYEE_NAME,
            src.DEPARTMENT,
            src.EMPLOYEE_STATUS,
            src.SALARY
        FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SOURCE AS src
        WHERE src.EMPLOYEE_STATUS = 'ACTIVE'
        QUALIFY ROW_NUMBER() OVER (
                    PARTITION BY src.EMPLOYEE_ID
                    ORDER BY src.UPDATED_TS DESC NULLS LAST, src.EMPLOYEE_ID
                ) = 1
    ) AS s
    ON tgt.EMPLOYEE_ID = s.EMPLOYEE_ID
    WHEN NOT MATCHED THEN
        INSERT (
            EMPLOYEE_ID,
            EMPLOYEE_NAME,
            DEPARTMENT,
            EMPLOYEE_STATUS,
            SALARY,
            LOAD_TS
        )
        VALUES (
            s.EMPLOYEE_ID,
            s.EMPLOYEE_NAME,
            s.DEPARTMENT,
            s.EMPLOYEE_STATUS,
            s.SALARY,
            CURRENT_TIMESTAMP()
        );

    RETURN 'SUCCESS';
END;
$$;
