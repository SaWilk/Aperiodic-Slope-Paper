% Test ICA issue

x = double(EEG.data(:));
fprintf('finite=%d  mean=%.3g  std=%.3g  min=%.3g  max=%.3g\n', ...
    all(isfinite(x)), mean(x), std(x), min(x), max(x));

% per-channel spread
sd_ch = std(double(EEG.data'), 0, 1);  % std across time, per channel
fprintf('channel std: median=%.3g  max=%.3g  min=%.3g\n', median(sd_ch), max(sd_ch), min(sd_ch));

% rank-ish / collapse check on a subset (avoid memory blowups)
T = min(20000, EEG.pnts);
X = double(EEG.data(:,1:T));
fprintf('corr offdiag median=%.3f\n', median(abs(corr(X') - eye(size(X,1))), 'all'));
