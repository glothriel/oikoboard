-- +goose Up

CREATE TABLE measurements (
    id            uuid PRIMARY KEY,
    household_id  uuid        NOT NULL,
    member_id     uuid        NOT NULL,
    measured_at   timestamptz NOT NULL,
    weight_kg     double precision NOT NULL CHECK (weight_kg > 0),
    impedance     int,
    -- body composition, computed on the device at save time (null: weight only)
    lbm_kg        double precision,
    fat_pct       double precision,
    water_pct     double precision,
    protein_pct   double precision,
    bone_kg       double precision,
    muscle_kg     double precision,
    bmr_kcal      double precision,
    visceral_fat  double precision,
    bmi           double precision,
    source        text        NOT NULL CHECK (source IN ('scale', 'manual')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    version       int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, member_id)
        REFERENCES members (household_id, id) ON DELETE CASCADE
);
CREATE INDEX measurements_idx ON measurements (household_id, measured_at DESC);

-- One row per member; the id is the member id.
CREATE TABLE fitness_profiles (
    id            uuid PRIMARY KEY,
    household_id  uuid        NOT NULL,
    sex           text        NOT NULL CHECK (sex IN ('male', 'female')),
    birth_date    date        NOT NULL,
    height_cm     double precision NOT NULL CHECK (height_cm > 0),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    version       int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, id)
        REFERENCES members (household_id, id) ON DELETE CASCADE
);

SELECT oiko_track('measurements');
SELECT oiko_track('fitness_profiles');

-- +goose Down
DROP TABLE fitness_profiles;
DROP TABLE measurements;
