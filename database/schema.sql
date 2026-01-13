-- ============================================================================
-- AMEP Database Schema - PostgreSQL 15+
-- Comprehensive schema supporting BR1-BR9
-- ============================================================================

-- ============================================================================
-- CORE USER TABLES
-- ============================================================================

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE students (
    student_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    grade_level INTEGER,
    section VARCHAR(50),
    enrollment_date DATE DEFAULT CURRENT_DATE,
    learning_style VARCHAR(50),  -- BR2: Personalization
    preferred_difficulty DECIMAL(3,2) DEFAULT 0.5  -- 0.0 to 1.0
);

CREATE TABLE teachers (
    teacher_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    subject_area VARCHAR(100),
    department VARCHAR(100),
    years_experience INTEGER
);

-- ============================================================================
-- CURRICULUM & CONTENT TABLES (BR1, BR2)
-- ============================================================================

CREATE TABLE curriculum_standards (
    standard_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    grade_level INTEGER,
    subject_area VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE concepts (
    concept_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    concept_name VARCHAR(255) NOT NULL,
    description TEXT,
    subject_area VARCHAR(100),
    difficulty_level DECIMAL(3,2) DEFAULT 0.5,  -- 0.0 to 1.0
    weight DECIMAL(3,2) DEFAULT 1.0,  -- Importance
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_difficulty CHECK (difficulty_level >= 0.0 AND difficulty_level <= 1.0)
);

-- Concept relationships for DKVMN (BR3)
CREATE TABLE concept_prerequisites (
    concept_id UUID REFERENCES concepts(concept_id) ON DELETE CASCADE,
    prerequisite_id UUID REFERENCES concepts(concept_id) ON DELETE CASCADE,
    correlation_weight DECIMAL(3,2) DEFAULT 0.5,
    PRIMARY KEY (concept_id, prerequisite_id)
);

CREATE TABLE content_items (
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    concept_id UUID REFERENCES concepts(concept_id) ON DELETE CASCADE,
    item_type VARCHAR(50) NOT NULL CHECK (item_type IN ('question', 'video', 'reading', 'exercise')),
    title VARCHAR(255),
    content TEXT NOT NULL,
    difficulty DECIMAL(3,2) NOT NULL,
    estimated_time INTEGER DEFAULT 5,  -- Minutes
    scaffolding_available BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES teachers(teacher_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_item_difficulty CHECK (difficulty >= 0.0 AND difficulty <= 1.0)
);

-- ============================================================================
-- KNOWLEDGE TRACING TABLES (BR1, BR2, BR3)
-- ============================================================================

CREATE TABLE student_concept_mastery (
    mastery_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    concept_id UUID REFERENCES concepts(concept_id) ON DELETE CASCADE,
    mastery_score DECIMAL(5,2) NOT NULL DEFAULT 30.0,  -- 0.00 to 100.00 (BR1)
    bkt_component DECIMAL(5,2),  -- BKT model contribution
    dkt_component DECIMAL(5,2),  -- DKT model contribution
    dkvmn_component DECIMAL(5,2),  -- DKVMN model contribution
    confidence DECIMAL(3,2),  -- 0.0 to 1.0
    learning_velocity DECIMAL(5,2) DEFAULT 0.0,  -- Rate of improvement
    last_assessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    times_assessed INTEGER DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(student_id, concept_id),
    CONSTRAINT check_mastery CHECK (mastery_score >= 0.0 AND mastery_score <= 100.0)
);

CREATE TABLE student_responses (
    response_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    item_id UUID REFERENCES content_items(item_id) ON DELETE CASCADE,
    concept_id UUID REFERENCES concepts(concept_id) ON DELETE CASCADE,
    is_correct BOOLEAN NOT NULL,
    response_time DECIMAL(6,2),  -- Seconds
    hints_used INTEGER DEFAULT 0,
    attempts INTEGER DEFAULT 1,
    response_text TEXT,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id UUID  -- Link to practice session
);

CREATE INDEX idx_student_responses_student ON student_responses(student_id);
CREATE INDEX idx_student_responses_concept ON student_responses(concept_id);

-- ============================================================================
-- ENGAGEMENT TRACKING TABLES (BR4, BR6)
-- ============================================================================

CREATE TABLE engagement_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    session_type VARCHAR(50) NOT NULL CHECK (session_type IN ('live_class', 'practice', 'project_work', 'assessment')),
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP,
    duration_minutes INTEGER,
    engagement_score DECIMAL(5,2)  -- 0.00 to 100.00
);

CREATE TABLE engagement_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    session_id UUID REFERENCES engagement_sessions(session_id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN ('login', 'page_view', 'interaction', 'resource_access', 'quiz_attempt', 'poll_response')),
    event_data JSONB,  -- Flexible data storage
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_engagement_logs_student ON engagement_logs(student_id);
CREATE INDEX idx_engagement_logs_timestamp ON engagement_logs(timestamp);

-- BR4: Anonymous live polling
CREATE TABLE live_polls (
    poll_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID REFERENCES teachers(teacher_id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    poll_type VARCHAR(50) DEFAULT 'multiple_choice',
    options JSONB NOT NULL,  -- Array of options
    correct_answer VARCHAR(255),  -- Optional for fact-based questions
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE poll_responses (
    response_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID REFERENCES live_polls(poll_id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    selected_option VARCHAR(255) NOT NULL,
    is_correct BOOLEAN,
    response_time DECIMAL(6,2),  -- Seconds to respond
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(poll_id, student_id)  -- One response per student per poll
);

-- BR4, BR6: Disengagement detection
CREATE TABLE disengagement_alerts (
    alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    alert_type VARCHAR(50) NOT NULL CHECK (alert_type IN ('quick_guess', 'bottom_out_hint', 'many_attempts', 'low_login_frequency', 'declining_performance')),
    severity VARCHAR(20) CHECK (severity IN ('MONITOR', 'AT_RISK', 'CRITICAL')),
    details JSONB,
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP,
    teacher_notified BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_disengagement_unresolved ON disengagement_alerts(student_id) WHERE resolved_at IS NULL;

-- ============================================================================
-- PROJECT-BASED LEARNING TABLES (BR5, BR9)
-- ============================================================================

CREATE TABLE projects (
    project_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID REFERENCES teachers(teacher_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    curriculum_alignment UUID REFERENCES curriculum_standards(standard_id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    current_stage VARCHAR(50) DEFAULT 'questioning' CHECK (current_stage IN ('questioning', 'define', 'research', 'create', 'present')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE teams (
    team_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    team_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE team_memberships (
    membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID REFERENCES teams(team_id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    role VARCHAR(100),  -- e.g., 'leader', 'researcher', 'designer'
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(team_id, student_id)
);

-- BR5: 4-Dimensional Team Effectiveness Model
CREATE TABLE soft_skill_assessments (
    assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID REFERENCES teams(team_id) ON DELETE CASCADE,
    assessed_student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,
    assessor_student_id UUID REFERENCES students(student_id) ON DELETE CASCADE,  -- Peer review
    assessment_type VARCHAR(50) DEFAULT 'peer_review' CHECK (assessment_type IN ('peer_review', 'self_assessment', 'teacher_assessment')),
    
    -- BR5: Team Dynamics (TD)
    td_communication DECIMAL(3,2),  -- 1.0 to 5.0 (Likert scale)
    td_mutual_support DECIMAL(3,2),
    td_trust DECIMAL(3,2),
    td_active_listening DECIMAL(3,2),
    
    -- BR5: Team Structure (TS)
    ts_clear_roles DECIMAL(3,2),
    ts_task_scheduling DECIMAL(3,2),
    ts_decision_making DECIMAL(3,2),
    ts_conflict_resolution DECIMAL(3,2),
    
    -- BR5: Team Motivation (TM)
    tm_clear_purpose DECIMAL(3,2),
    tm_smart_goals DECIMAL(3,2),
    tm_passion DECIMAL(3,2),
    tm_synergy DECIMAL(3,2),
    
    -- BR5: Team Excellence (TE)
    te_growth_mindset DECIMAL(3,2),
    te_quality_work DECIMAL(3,2),
    te_self_monitoring DECIMAL(3,2),
    te_reflective_practice DECIMAL(3,2),
    
    overall_td_score DECIMAL(4,2),  -- Computed average
    overall_ts_score DECIMAL(4,2),
    overall_tm_score DECIMAL(4,2),
    overall_te_score DECIMAL(4,2),
    
    comments TEXT,
    assessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT check_likert_range CHECK (
        td_communication BETWEEN 1.0 AND 5.0 AND
        td_mutual_support BETWEEN 1.0 AND 5.0 AND
        td_trust BETWEEN 1.0 AND 5.0 AND
        td_active_listening BETWEEN 1.0 AND 5.0 AND
        ts_clear_roles BETWEEN 1.0 AND 5.0 AND
        ts_task_scheduling BETWEEN 1.0 AND 5.0 AND
        ts_decision_making BETWEEN 1.0 AND 5.0 AND
        ts_conflict_resolution BETWEEN 1.0 AND 5.0 AND
        tm_clear_purpose BETWEEN 1.0 AND 5.0 AND
        tm_smart_goals BETWEEN 1.0 AND 5.0 AND
        tm_passion BETWEEN 1.0 AND 5.0 AND
        tm_synergy BETWEEN 1.0 AND 5.0 AND
        te_growth_mindset BETWEEN 1.0 AND 5.0 AND
        te_quality_work BETWEEN 1.0 AND 5.0 AND
        te_self_monitoring BETWEEN 1.0 AND 5.0 AND
        te_reflective_practice BETWEEN 1.0 AND 5.0
    )
);

CREATE INDEX idx_soft_skills_team ON soft_skill_assessments(team_id);
CREATE INDEX idx_soft_skills_assessed ON soft_skill_assessments(assessed_student_id);

-- BR9: Project artifacts and milestones
CREATE TABLE project_milestones (
    milestone_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    team_id UUID REFERENCES teams(team_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    due_date DATE NOT NULL,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'overdue')),
    completed_at TIMESTAMP
);

CREATE TABLE project_artifacts (
    artifact_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID REFERENCES teams(team_id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    artifact_type VARCHAR(50) CHECK (artifact_type IN ('document', 'presentation', 'code', 'video', 'other')),
    file_name VARCHAR(255),
    file_url TEXT,
    version INTEGER DEFAULT 1,
    uploaded_by UUID REFERENCES students(student_id),
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEACHER PRODUCTIVITY TABLES (BR7, BR8)
-- ============================================================================

CREATE TABLE curriculum_templates (
    template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    subject_area VARCHAR(100),
    grade_level INTEGER,
    template_type VARCHAR(50) CHECK (template_type IN ('lesson_plan', 'project_brief', 'assessment', 'rubric')),
    content JSONB NOT NULL,  -- Structured template content
    learning_objectives TEXT[],
    estimated_duration INTEGER,  -- Minutes
    soft_skills_targeted VARCHAR(100)[],  -- e.g., ['collaboration', 'communication']
    created_by UUID REFERENCES teachers(teacher_id),
    is_public BOOLEAN DEFAULT FALSE,
    times_used INTEGER DEFAULT 0,
    avg_rating DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_templates_subject_grade ON curriculum_templates(subject_area, grade_level);

-- BR7: Collaborative planning
CREATE TABLE template_collaborations (
    collaboration_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID REFERENCES curriculum_templates(template_id) ON DELETE CASCADE,
    teacher_id UUID REFERENCES teachers(teacher_id) ON DELETE CASCADE,
    contribution_type VARCHAR(50) CHECK (contribution_type IN ('creator', 'editor', 'reviewer')),
    contributed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- BR8: Unified reporting metrics
CREATE TABLE institutional_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_date DATE DEFAULT CURRENT_DATE,
    
    -- BR8: Three core metrics
    mastery_rate DECIMAL(5,2),  -- Average class mastery (0-100)
    teacher_adoption_rate DECIMAL(5,2),  -- Platform usage by teachers (0-100)
    admin_confidence_score DECIMAL(5,2),  -- Data completeness & reliability (0-100)
    
    -- Supporting metrics
    total_students INTEGER,
    active_students INTEGER,
    total_teachers INTEGER,
    active_teachers INTEGER,
    total_concepts_taught INTEGER,
    avg_engagement_score DECIMAL(5,2),
    
    -- BR7: Workload metrics
    avg_planning_time_minutes DECIMAL(6,2),  -- Per teacher
    data_entry_events INTEGER,  -- Track reduction goal
    
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- BR6, BR8: Intervention tracking
CREATE TABLE teacher_interventions (
    intervention_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID REFERENCES teachers(teacher_id) ON DELETE CASCADE,
    concept_id UUID REFERENCES concepts(concept_id),
    intervention_type VARCHAR(50) CHECK (intervention_type IN ('re_explanation', 'additional_practice', 'one_on_one', 'group_activity', 'scaffolding')),
    target_students UUID[],  -- Array of student IDs
    description TEXT,
    mastery_before DECIMAL(5,2),
    mastery_after DECIMAL(5,2),
    improvement DECIMAL(5,2),  -- Calculated: mastery_after - mastery_before
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    measured_at TIMESTAMP  -- When post-intervention measurement occurred
);

CREATE INDEX idx_interventions_teacher ON teacher_interventions(teacher_id);

-- ============================================================================
-- VIEWS FOR REPORTING (BR6, BR8)
-- ============================================================================

-- BR8: Unified Dashboard View
CREATE VIEW unified_class_metrics AS
SELECT 
    c.concept_name,
    AVG(scm.mastery_score) as avg_mastery,
    COUNT(DISTINCT scm.student_id) as students_assessed,
    COUNT(DISTINCT CASE WHEN scm.mastery_score >= 85 THEN scm.student_id END) as students_mastered,
    AVG(scm.learning_velocity) as avg_learning_velocity
FROM student_concept_mastery scm
JOIN concepts c ON scm.concept_id = c.concept_id
GROUP BY c.concept_id, c.concept_name;

-- BR6: Real-time engagement view
CREATE VIEW current_engagement_status AS
SELECT 
    s.student_id,
    s.first_name,
    s.last_name,
    AVG(es.engagement_score) as avg_engagement,
    COUNT(el.log_id) as activity_count,
    MAX(el.timestamp) as last_active,
    CASE 
        WHEN COUNT(da.alert_id) > 0 THEN 'AT_RISK'
        WHEN AVG(es.engagement_score) < 60 THEN 'MONITOR'
        ELSE 'ENGAGED'
    END as status
FROM students s
LEFT JOIN engagement_sessions es ON s.student_id = es.student_id
LEFT JOIN engagement_logs el ON s.student_id = el.student_id
LEFT JOIN disengagement_alerts da ON s.student_id = da.student_id AND da.resolved_at IS NULL
WHERE el.timestamp > CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY s.student_id, s.first_name, s.last_name;

-- BR5: Team performance summary
CREATE VIEW team_soft_skills_summary AS
SELECT 
    t.team_id,
    t.team_name,
    p.title as project_title,
    AVG(ssa.overall_td_score) as avg_team_dynamics,
    AVG(ssa.overall_ts_score) as avg_team_structure,
    AVG(ssa.overall_tm_score) as avg_team_motivation,
    AVG(ssa.overall_te_score) as avg_team_excellence,
    COUNT(ssa.assessment_id) as total_assessments
FROM teams t
JOIN projects p ON t.project_id = p.project_id
LEFT JOIN soft_skill_assessments ssa ON t.team_id = ssa.team_id
GROUP BY t.team_id, t.team_name, p.title;

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Auto-update timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mastery_updated_at BEFORE UPDATE ON student_concept_mastery
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-calculate soft skill dimension averages
CREATE OR REPLACE FUNCTION calculate_soft_skill_averages()
RETURNS TRIGGER AS $$
BEGIN
    NEW.overall_td_score = (NEW.td_communication + NEW.td_mutual_support + NEW.td_trust + NEW.td_active_listening) / 4.0;
    NEW.overall_ts_score = (NEW.ts_clear_roles + NEW.ts_task_scheduling + NEW.ts_decision_making + NEW.ts_conflict_resolution) / 4.0;
    NEW.overall_tm_score = (NEW.tm_clear_purpose + NEW.tm_smart_goals + NEW.tm_passion + NEW.tm_synergy) / 4.0;
    NEW.overall_te_score = (NEW.te_growth_mindset + NEW.te_quality_work + NEW.te_self_monitoring + NEW.te_reflective_practice) / 4.0;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_soft_skills BEFORE INSERT OR UPDATE ON soft_skill_assessments
    FOR EACH ROW EXECUTE FUNCTION calculate_soft_skill_averages();

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX idx_mastery_student_concept ON student_concept_mastery(student_id, concept_id);
CREATE INDEX idx_mastery_score ON student_concept_mastery(mastery_score);
CREATE INDEX idx_responses_session ON student_responses(session_id);
CREATE INDEX idx_polls_active ON live_polls(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_templates_public ON curriculum_templates(is_public) WHERE is_public = TRUE;

-- ============================================================================
-- SAMPLE DATA (Minimal seed for testing)
-- ============================================================================

-- This would be in a separate seed_data.sql file
-- INSERT INTO users (user_id, email, username, password_hash, role) VALUES ...