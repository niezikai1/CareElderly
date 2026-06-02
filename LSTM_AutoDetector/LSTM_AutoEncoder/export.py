import shutil
import torch
import torch.nn as nn
import coremltools as ct
from pathlib import Path

BASE_DIR    = Path(__file__).parent
HIDDEN_SIZE = 32   # per-direction; bidirectional encoder outputs HIDDEN_SIZE*2 = 64
SEQ_LEN     = 30
NUM_LAYERS = 2

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


model = AutoEncoder()
model.load_state_dict(torch.load(BASE_DIR.parent / 'vital_autoencoder.pth',
                                  weights_only=True, map_location='cpu'))
model.eval()
print('Model loaded.')

dummy_input  = torch.zeros(1, SEQ_LEN, 2)
traced_model = torch.jit.trace(model, dummy_input)

mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name='vitals', shape=(1, SEQ_LEN, 2))],
    outputs=[ct.TensorType(name='reconstruction')],
    minimum_deployment_target=ct.target.iOS16,
)

out_path = BASE_DIR.parent / 'VitalAnomalyDetector.mlpackage'
if out_path.exists():
    shutil.rmtree(out_path)

mlmodel.save(str(out_path))
print(f'Core ML model saved → {out_path}')
