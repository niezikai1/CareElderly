import torch
import torch.nn as nn
import numpy as np
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path
from torch.utils.data import DataLoader, TensorDataset
from sklearn.metrics import roc_curve, auc, precision_recall_curve, average_precision_score

SEQ_LEN     = 30
HIDDEN_SIZE = 32
NUM_LAYERS  = 2

BASE_DIR  = Path(__file__).parent
SAVE_PATH = BASE_DIR.parent / 'vital_autoencoder.pth'
PLOT_DIR  = BASE_DIR.parent / 'plots'


class Encoder(nn.Module):
    def __init__(self, input_size=2, hidden_size=HIDDEN_SIZE, num_layers=NUM_LAYERS):
        super().__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, num_layers=num_layers,
                            batch_first=True, bidirectional=True)

    def forward(self, x):
        _, (h, _) = self.lstm(x)
        h_forward = h[-2]
        h_backward = h[-1]
        return torch.cat((h_forward, h_backward), dim=1)


class Decoder(nn.Module):
    def __init__(self, hidden_size=HIDDEN_SIZE, output_size=2,
                 num_layers=NUM_LAYERS, seq_len=SEQ_LEN):
        super().__init__()
        self.seq_len = seq_len
        double_hidden = hidden_size * 2
        self.lstm = nn.LSTM(double_hidden, double_hidden, num_layers=num_layers,
                            batch_first=True)
        self.fc = nn.Linear(double_hidden, output_size)

    def forward(self, z):
        out, _ = self.lstm(z.unsqueeze(1).repeat(1, self.seq_len, 1))
        return self.fc(out)


class AutoEncoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.encoder = Encoder()
        self.decoder = Decoder()

    def forward(self, x):
        return self.decoder(self.encoder(x))


def _batch_mse(model, data, device, batch_size=256):
    """Mean MSE loss over an entire dataset, evaluated in batches."""
    loader = DataLoader(TensorDataset(data), batch_size=batch_size, shuffle=False)
    criterion = nn.MSELoss()
    total = 0.0
    model.eval()
    with torch.no_grad():
        for (b,) in loader:
            b = b.to(device)
            total += criterion(model(b), b).item()
    return total / len(loader)


def train(model, train_data, val_data, device, epochs=300, lr=0.001, batch_size=64):
    loader = DataLoader(TensorDataset(train_data), batch_size=batch_size,
                        shuffle=True, drop_last=True)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()
    best_loss = float('inf')
    train_losses, val_losses = [], []

    for epoch in range(1, epochs + 1):
        model.train()
        total_loss = 0.0
        for (b,) in loader:
            b = b.to(device)
            optimizer.zero_grad()
            loss = criterion(model(b), b)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
        epoch_loss = total_loss / len(loader)
        val_loss = _batch_mse(model, val_data, device)

        train_losses.append(epoch_loss)
        val_losses.append(val_loss)

        if epoch % 30 == 0:
            print(f'Epoch {epoch:03d}  train={epoch_loss:.6f}  val={val_loss:.6f}')

        if epoch_loss < best_loss:
            best_loss = epoch_loss
            torch.save(model.state_dict(), SAVE_PATH)

    return train_losses, val_losses


def get_reconstruction_errors(model, data, device):
    """Per-sample MSE reconstruction error array."""
    model.eval()
    criterion = nn.MSELoss()
    errors = []
    with torch.no_grad():
        for i in range(len(data)):
            sample = data[i:i+1].to(device)
            errors.append(criterion(model(sample), sample).item())
    return np.array(errors)


def compute_threshold(model, data, device):
    """95th-percentile reconstruction error on the test set."""
    errors = get_reconstruction_errors(model, data, device)
    return float(np.percentile(errors, 95))


def make_synthetic_anomalies(normal_data, n_samples=None, seed=42):
    """
    Synthesise anomalous windows from normal data using three perturbation
    strategies: spike injection, large Gaussian noise, sudden value shift.
    Returns a float32 tensor of shape (n_samples, SEQ_LEN, 2).
    """
    rng = np.random.default_rng(seed)
    if n_samples is None:
        n_samples = len(normal_data)
    data_np = normal_data.numpy()
    anomalies = []

    for _ in range(n_samples):
        win = data_np[rng.integers(len(data_np))].copy()
        method = rng.integers(3)

        if method == 0:
            # Spike: replace a short segment with extreme values
            spike_len = int(rng.integers(3, 10))
            start = int(rng.integers(0, SEQ_LEN - spike_len))
            channel = int(rng.integers(2))
            direction = rng.choice([-1.0, 1.0])
            win[start:start + spike_len, channel] += direction * rng.uniform(0.8, 1.5)
        elif method == 1:
            # Large Gaussian noise across the whole window
            win += rng.normal(0, 0.45, win.shape)
        else:
            # Sudden step change from a random midpoint onward
            split = int(rng.integers(5, SEQ_LEN - 5))
            direction = rng.choice([-1.0, 1.0])
            win[split:, :] += direction * rng.uniform(0.5, 1.2)

        anomalies.append(win)

    return torch.tensor(np.array(anomalies, dtype=np.float32))


def visualize_results(train_losses, val_losses, normal_errors, anomaly_errors,
                      threshold, save_dir):
    save_dir = Path(save_dir)
    save_dir.mkdir(parents=True, exist_ok=True)

    roc_auc, avg_precision, fpr, tpr, precision, recall = _compute_roc_pr(
        normal_errors, anomaly_errors
    )

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle('LSTM Autoencoder — Training Results', fontsize=15, fontweight='bold')

    # ── 1. Loss curves ────────────────────────────────────────────────────
    ax = axes[0, 0]
    epochs = range(1, len(train_losses) + 1)
    ax.plot(epochs, train_losses, label='Train Loss', color='steelblue', linewidth=1.5)
    ax.plot(epochs, val_losses,   label='Val Loss',   color='tomato',    linewidth=1.5,
            linestyle='--')
    ax.set_xlabel('Epoch')
    ax.set_ylabel('MSE Loss (log scale)')
    ax.set_title('Training & Validation Loss')
    ax.set_yscale('log')
    ax.legend()
    ax.grid(True, alpha=0.3)

    # ── 2. ROC curve ──────────────────────────────────────────────────────
    ax = axes[0, 1]
    ax.plot(fpr, tpr, color='darkorange', linewidth=2,
            label=f'ROC AUC = {roc_auc:.4f}')
    ax.plot([0, 1], [0, 1], 'k--', linewidth=1, alpha=0.5, label='Random')
    ax.set_xlabel('False Positive Rate')
    ax.set_ylabel('True Positive Rate')
    ax.set_title('ROC Curve (Normal vs Synthetic Anomaly)')
    ax.legend(loc='lower right')
    ax.grid(True, alpha=0.3)

    # ── 3. Precision-Recall curve ─────────────────────────────────────────
    ax = axes[1, 0]
    ax.plot(recall, precision, color='mediumseagreen', linewidth=2,
            label=f'Avg Precision = {avg_precision:.4f}')
    ax.axhline(0.5, color='k', linestyle='--', linewidth=1, alpha=0.5,
               label='Random baseline')
    ax.set_xlabel('Recall')
    ax.set_ylabel('Precision')
    ax.set_title('Precision-Recall Curve')
    ax.legend()
    ax.grid(True, alpha=0.3)

    # ── 4. Reconstruction error distribution ─────────────────────────────
    ax = axes[1, 1]
    max_err = float(np.percentile(np.concatenate([normal_errors, anomaly_errors]), 99))
    bins = np.linspace(0, max_err, 60)
    ax.hist(normal_errors,  bins=bins, alpha=0.6, color='steelblue',
            label='Normal (test)', density=True)
    ax.hist(anomaly_errors, bins=bins, alpha=0.6, color='tomato',
            label='Anomaly (synthetic)', density=True)
    ax.axvline(threshold, color='black', linestyle='--', linewidth=1.8,
               label=f'Threshold (95th) = {threshold:.5f}')
    ax.set_xlabel('Reconstruction MSE')
    ax.set_ylabel('Density')
    ax.set_title('Reconstruction Error Distribution')
    ax.legend()
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    out_path = save_dir / 'training_results.png'
    plt.savefig(out_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f'Plot saved → {out_path}')

    # ── Save numeric summary ──────────────────────────────────────────────
    summary = {
        'roc_auc':       round(roc_auc, 6),
        'avg_precision': round(avg_precision, 6),
        'threshold_95th': round(threshold, 8),
        'final_train_loss': round(train_losses[-1], 8),
        'final_val_loss':   round(val_losses[-1], 8),
    }
    summary_path = save_dir / 'metrics_summary.json'
    json.dump(summary, open(summary_path, 'w'), indent=2)
    print(f'Metrics summary → {summary_path}')
    return summary


def _compute_roc_pr(normal_errors, anomaly_errors):
    y_true  = np.concatenate([np.zeros(len(normal_errors)),
                               np.ones(len(anomaly_errors))])
    y_score = np.concatenate([normal_errors, anomaly_errors])
    fpr, tpr, _ = roc_curve(y_true, y_score)
    roc_auc      = auc(fpr, tpr)
    precision, recall, _ = precision_recall_curve(y_true, y_score)
    avg_precision = average_precision_score(y_true, y_score)
    return roc_auc, avg_precision, fpr, tpr, precision, recall


# ── Main ─────────────────────────────────────────────────────────────────
data  = np.load(BASE_DIR.parent / 'data.npy')
split = int(0.8 * len(data))
train_tensor = torch.tensor(data[:split], dtype=torch.float32)
test_tensor  = torch.tensor(data[split:],  dtype=torch.float32)
print(f'Train: {train_tensor.shape}  Test: {test_tensor.shape}')

device = torch.device(
    'mps'  if torch.backends.mps.is_available() else
    'cuda' if torch.cuda.is_available()         else 'cpu'
)
print(f'Device: {device}')

model = AutoEncoder().to(device)
train_losses, val_losses = train(model, train_tensor, test_tensor, device)

model.load_state_dict(torch.load(SAVE_PATH, weights_only=True, map_location=device))
model.eval()
with torch.no_grad():
    for label, s in [('Train[0]', train_tensor[:1]), ('Test[0]', test_tensor[:1])]:
        s = s.to(device)
        r = model(s)
        print(f'{label}  Input: {s[0,0,:].cpu()}  Rebuild: {r[0,0,:].cpu()}')

threshold = compute_threshold(model, test_tensor, device)
print(f'Threshold (95th, test-set): {threshold:.6f}')
json.dump({'threshold': threshold},
          open(BASE_DIR.parent / 'threshold_test.json', 'w'), indent=2)

# ── Visualisation ─────────────────────────────────────────────────────────
print('\nComputing reconstruction errors for visualisation...')
normal_errors  = get_reconstruction_errors(model, test_tensor, device)
anomaly_tensor = make_synthetic_anomalies(test_tensor, n_samples=len(test_tensor))
anomaly_errors = get_reconstruction_errors(model, anomaly_tensor, device)

summary = visualize_results(train_losses, val_losses, normal_errors, anomaly_errors,
                             threshold, save_dir=PLOT_DIR)

print(f'\nROC AUC:        {summary["roc_auc"]:.4f}')
print(f'Avg Precision:  {summary["avg_precision"]:.4f}')
print('Done.')