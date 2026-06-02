from pathlib import Path
import pandas as pd
import numpy as np

SCRIPT_DIR = Path(__file__).parent
CSV_DIR    = SCRIPT_DIR / 'bidmc-ppg-and-respiration-dataset-1.0.0' / 'bidmc_csv'
OUT_PATH   = SCRIPT_DIR.parent / 'data.npy'

all_df = []
for idx in range(1, 54):
    df_temp = pd.read_csv(CSV_DIR / f'bidmc_{idx:02d}_Numerics.csv')
    df_temp = df_temp[[' HR', ' RESP']]
    df_temp = df_temp[
        (df_temp[' HR']   >= 50) & (df_temp[' HR']   <= 100) &
        (df_temp[' RESP'] >= 12) & (df_temp[' RESP'] <= 20)
    ]
    all_df.append(df_temp)

df = pd.concat(all_df, ignore_index=True)
print(f'Samples after filtering: {len(df)}')

windows = []
for i in range(0, len(df) - 30, 15):
    windows.append(df.iloc[i:i+30].values)

data = np.array(windows)
print(f'Windows: {data.shape}')

data[:, :, 0] = (data[:, :, 0] - 50) / (100 - 50)  # HR   → [0, 1]
data[:, :, 1] = (data[:, :, 1] - 12) / (20  - 12)  # RESP → [0, 1]

print(f'HR   range: [{data[:,:,0].min():.3f}, {data[:,:,0].max():.3f}]')
print(f'RESP range: [{data[:,:,1].min():.3f}, {data[:,:,1].max():.3f}]')

np.save(OUT_PATH, data)
print(f'Saved → {OUT_PATH}')
