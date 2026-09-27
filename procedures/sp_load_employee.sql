-- ============================================================================
-- Procedure : MULTI_AGENT_SDLC_POC.DEV.SP_LOAD_EMPLOYEE
-- Jira      : SCRUM-1 - Load only active employees and prevent duplicates
-- Purpose   : Load ACTIVE employees from the source table into EMPLOYEE_TARGET
--             while guaranteeing EMPLOYEE_ID uniqueness in the target.
--             Also loads employee skills into EMPLOYEE_SKILLS_TARGET,
--             populates a comma-separated SKILLS column, and derives GRADE.
--
-- Acceptance criteria implemented:
--   * Only ACTIVE employees are loaded.
--   * EMPLOYEE_ID is unique in the target.
--   * If duplicate source records exist, only one is loaded.
--   * Employees already present in the target are not inserted again.
--   * Employee skills for active employees are loaded into EMPLOYEE_SKILLS_TARGET.
--   * SKILLS column in EMPLOYEE_TARGET is populated from EMPLOYEE_SKILLS.
--   * GRADE is derived from SALARY (A/B/C/D).
--   * The procedure returns 'SUCCESS' after successful completion.
--
-- Live schema columns (verified via INFORMATION_SCHEMA):
--   EMPLOYEE_SOURCE : EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT,
--                     EMPLOYEE_STATUS, SALARY, MANAGER_ID,
--                     MANAGER_NAME, EMPLOYEE_DESIGNATION, UPDATED_TS
--   EMPLOYEE_TARGET : EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT,
--                     EMPLOYEE_STATUS, SALARY, MANAGER_ID,
--                     MANAGER_NAME, EMPLOYEE_DESIGNATION, SKILLS, GRADE, LOAD_TS
--   EMPLOYEE_SKILLS : EMP_ID, ENAME, SKILL_ID, SKILL_NAME
--   EMPLOYEE_SKILLS_TARGET : EMP_ID, ENAME, SKILL_ID, SKILL_NAME, LOAD_TS
-- ============================================================================

CREATE OR REPLACE PROCEDURE MULTI_AGENT_SDLC_POC.DEV.SP_LOAD_EMPLOYEE()
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS OWNER
AS
$$
BEGIN
    -- Step 1: Load active, de-duplicated employees into EMPLOYEE_TARGET
    MERGE INTO MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET AS tgt
    USING (
        SELECT
            src.EMPLOYEE_ID,
            src.EMPLOYEE_NAME,
            src.DEPARTMENT,
            src.EMPLOYEE_STATUS,
            src.SALARY,
            src.MANAGER_ID,
            src.MANAGER_NAME,
            src.EMPLOYEE_DESIGNATION
        FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SOURCE AS src
        WHERE UPPER(TRIM(src.EMPLOYEE_STATUS)) = 'ACTIVE'
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
            MANAGER_ID,
            MANAGER_NAME,
            EMPLOYEE_DESIGNATION,
            LOAD_TS
        )
        VALUES (
            s.EMPLOYEE_ID,
            s.EMPLOYEE_NAME,
            s.DEPARTMENT,
            s.EMPLOYEE_STATUS,
            s.SALARY,
            s.MANAGER_ID,
            s.MANAGER_NAME,
            s.EMPLOYEE_DESIGNATION,
            CURRENT_TIMESTAMP()
        );

    -- Step 2: Load employee skills into EMPLOYEE_SKILLS_TARGET
    MERGE INTO MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SKILLS_TARGET AS tgt
    USING (
        SELECT
            sk.EMP_ID,
            sk.ENAME,
            sk.SKILL_ID,
            sk.SKILL_NAME
        FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SKILLS AS sk
        WHERE sk.EMP_ID IN (
            SELECT EMPLOYEE_ID
            FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET
        )
        QUALIFY ROW_NUMBER() OVER (
                    PARTITION BY sk.EMP_ID, sk.SKILL_ID
                    ORDER BY sk.EMP_ID
                ) = 1
    ) AS s
    ON tgt.EMP_ID = s.EMP_ID AND tgt.SKILL_ID = s.SKILL_ID
    WHEN NOT MATCHED THEN
        INSERT (
            EMP_ID,
            ENAME,
            SKILL_ID,
            SKILL_NAME,
            LOAD_TS
        )
        VALUES (
            s.EMP_ID,
            s.ENAME,
            s.SKILL_ID,
            s.SKILL_NAME,
            CURRENT_TIMESTAMP()
        );

    -- Step 3: Populate SKILLS column in EMPLOYEE_TARGET from EMPLOYEE_SKILLS
    MERGE INTO MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET AS tgt
    USING (
        SELECT sk.EMP_ID,
               LISTAGG(sk.SKILL_NAME, ', ') WITHIN GROUP (ORDER BY sk.SKILL_ID) AS SKILLS
        FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_SKILLS AS sk
        WHERE sk.EMP_ID IN (SELECT EMPLOYEE_ID FROM MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET)
        GROUP BY sk.EMP_ID
    ) AS s
    ON tgt.EMPLOYEE_ID = s.EMP_ID
    WHEN MATCHED THEN UPDATE SET tgt.SKILLS = s.SKILLS;

    -- Step 4: Derive GRADE in EMPLOYEE_TARGET based on SALARY
    --   A = 100,000+  |  B = 80,000-99,999  |  C = 60,000-79,999  |  D = below 60,000
    UPDATE MULTI_AGENT_SDLC_POC.DEV.EMPLOYEE_TARGET
    SET GRADE = CASE
        WHEN SALARY >= 100000 THEN 'A'
        WHEN SALARY >= 80000  THEN 'B'
        WHEN SALARY >= 60000  THEN 'C'
        ELSE 'D'
    END;

    RETURN 'SUCCESS';
END;
$$;
