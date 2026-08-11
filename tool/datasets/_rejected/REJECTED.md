# Rejected Datasets

This folder contains raw datasets that were initially reviewed during the v1.0-ghana-baseline data audit but were **explicitly rejected** for use in training any CareBridge AI production models.

## Why are they here?
They are kept in the repository purely as documented negative examples (the rejected baselines) for audit transparency.

## Clinical Hazard Reasons:

### `pima_indians_diabetes.csv`
- **Reason:** Pima Indians Diabetes is a cross-domain dataset (diabetes in adult women) and is a complete clinical mismatch for neonatal sepsis (PSBI). Using it to predict neonatal outcomes is a clinical hazard.

### `haberman_survival.csv`
- **Reason:** Haberman is breast-cancer survival data. Like Pima, it bears no clinical or epidemiological relevance to maternal/child health risks in Northern Ghana.

> **WARNING:**
> The training pipeline (`tool/train_model_pack.py`) does **not** read from this directory. Do not move these files back to the main datasets folder.
