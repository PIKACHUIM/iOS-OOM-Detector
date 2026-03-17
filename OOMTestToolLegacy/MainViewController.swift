import UIKit

final class MainViewController: UIViewController {
    
    private let allocator = MemoryAllocator()
    private let logger = OOMLogger.shared
    
    // MARK: - UI Elements
    
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    
    // Crash banner
    private let crashBannerView = UIView()
    private let crashTitleLabel = UILabel()
    private let crashMemoryLabel = UILabel()
    private let crashBlocksLabel = UILabel()
    private let crashIntervalLabel = UILabel()
    private let crashTimeLabel = UILabel()
    
    // Monitor card
    private let monitorCard = UIView()
    private let monitorTitleLabel = UILabel()
    private let runningDot = UIView()
    private let runningLabel = UILabel()
    private let memoryValueLabel = UILabel()
    private let memoryUnitLabel = UILabel()
    private let blocksStatLabel = UILabel()
    private let chunkStatLabel = UILabel()
    private let intervalStatLabel = UILabel()
    
    // Config card
    private let configCard = UIView()
    private let chunkTextField = UITextField()
    private let holdTimeTextField = UITextField()
    
    // Action button
    private let actionButton = UIButton(type: .system)
    
    // Status
    private let statusLabel = UILabel()
    
    // Log card
    private let logCard = UIView()
    private let logTitleLabel = UILabel()
    private let logCountLabel = UILabel()
    private let logStack = UIStackView()
    
    // Colors
    private let cardBg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.15, alpha: 1)
            : UIColor.white
    }
    private let pageBg = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 1)
            : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "OOM 测试工具"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        allocator.delegate = self
        setupUI()
        checkLastSession()
        setupNavBarButtons()
    }
    
    // MARK: - Nav Bar
    
    private func setupNavBarButtons() {
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle") ?? makeEllipsisImage(),
            style: .plain,
            target: self,
            action: #selector(showMenu)
        )
        navigationItem.rightBarButtonItem = menuButton
    }
    
    private func makeEllipsisImage() -> UIImage? {
        let size = CGSize(width: 24, height: 24)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let tint = navigationController?.navigationBar.tintColor ?? .systemBlue
        ctx.setFillColor(tint.cgColor)
        let dotSize: CGFloat = 4
        let spacing: CGFloat = 6
        let totalW = dotSize * 3 + spacing * 2
        let startX = (size.width - totalW) / 2
        let y = (size.height - dotSize) / 2
        for i in 0..<3 {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: dotSize, height: dotSize))
        }
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img?.withRenderingMode(.alwaysTemplate)
    }
    
    @objc private func showMenu() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "📋 历史记录", style: .default) { [weak self] _ in
            self?.showHistory()
        })
        alert.addAction(UIAlertAction(title: "🗑 清除日志", style: .destructive) { [weak self] _ in
            self?.confirmClearLogs()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
    
    private func showHistory() {
        let vc = HistoryViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    private func confirmClearLogs() {
        let alert = UIAlertController(title: "清除所有日志", message: "确定要清除所有测试日志吗？此操作不可撤销。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.logger.clearLogs()
            self?.crashBannerView.isHidden = true
        })
        present(alert, animated: true)
    }
    
    // MARK: - Setup UI
    
    private func setupUI() {
        view.backgroundColor = pageBg
        
        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        
        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
        
        setupCrashBanner()
        setupMonitorCard()
        setupConfigCard()
        setupActionButton()
        setupStatusLabel()
        setupLogCard()
        
        // 初始状态
        crashBannerView.isHidden = true
        monitorCard.isHidden = true
        logCard.isHidden = true
    }
    
    // MARK: - Crash Banner
    
    private func setupCrashBanner() {
        crashBannerView.layer.cornerRadius = 16
        crashBannerView.clipsToBounds = true
        
        // Gradient background
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9).cgColor,
            UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.9).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        crashBannerView.layer.insertSublayer(gradient, at: 0)
        crashBannerView.tag = 999
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        crashBannerView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: crashBannerView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: crashBannerView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: crashBannerView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: crashBannerView.bottomAnchor, constant: -16),
        ])
        
        crashTitleLabel.text = "⚠️ 检测到上次 OOM 崩溃"
        crashTitleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        crashTitleLabel.textColor = .white
        stack.addArrangedSubview(crashTitleLabel)
        
        for label in [crashMemoryLabel, crashBlocksLabel, crashIntervalLabel, crashTimeLabel] {
            label.font = UIFont.systemFont(ofSize: 14)
            label.textColor = UIColor(white: 1, alpha: 0.9)
            stack.addArrangedSubview(label)
        }
        
        contentStack.addArrangedSubview(crashBannerView)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let gradient = crashBannerView.layer.sublayers?.first as? CAGradientLayer {
            gradient.frame = crashBannerView.bounds
        }
    }
    
    // MARK: - Monitor Card
    
    private func setupMonitorCard() {
        styleCard(monitorCard)
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        monitorCard.addSubview(stack)
        pinToCard(stack, in: monitorCard)
        
        // Title row
        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        
        monitorTitleLabel.text = "📊 实时监控"
        monitorTitleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        titleRow.addArrangedSubview(monitorTitleLabel)
        
        let spacer = UIView()
        titleRow.addArrangedSubview(spacer)
        
        runningDot.backgroundColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
        runningDot.layer.cornerRadius = 4
        runningDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            runningDot.widthAnchor.constraint(equalToConstant: 8),
            runningDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        titleRow.addArrangedSubview(runningDot)
        
        runningLabel.text = "运行中"
        runningLabel.font = UIFont.systemFont(ofSize: 12)
        runningLabel.textColor = .gray
        titleRow.addArrangedSubview(runningLabel)
        
        stack.addArrangedSubview(titleRow)
        
        // Memory value
        memoryValueLabel.text = "0.0"
        memoryValueLabel.font = UIFont(name: "HelveticaNeue-Bold", size: 56) ?? UIFont.boldSystemFont(ofSize: 56)
        memoryValueLabel.textColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
        memoryValueLabel.textAlignment = .center
        stack.addArrangedSubview(memoryValueLabel)
        
        memoryUnitLabel.text = "MB 已分配"
        memoryUnitLabel.font = UIFont.systemFont(ofSize: 15)
        memoryUnitLabel.textColor = .gray
        memoryUnitLabel.textAlignment = .center
        stack.addArrangedSubview(memoryUnitLabel)
        
        // Separator
        let sep = UIView()
        sep.backgroundColor = UIColor(white: 0.85, alpha: 1)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(sep)
        
        // Stats row
        let statsRow = UIStackView()
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 12
        
        blocksStatLabel.text = "0"
        chunkStatLabel.text = "10 MB"
        intervalStatLabel.text = "100 ms"
        
        statsRow.addArrangedSubview(makeStatView(valueLabel: blocksStatLabel, title: "块数", emoji: "📦"))
        statsRow.addArrangedSubview(makeStatView(valueLabel: chunkStatLabel, title: "块大小", emoji: "📐"))
        statsRow.addArrangedSubview(makeStatView(valueLabel: intervalStatLabel, title: "间隔", emoji: "⏱"))
        
        stack.addArrangedSubview(statsRow)
        
        contentStack.addArrangedSubview(monitorCard)
    }
    
    private func makeStatView(valueLabel: UILabel, title: String, emoji: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        
        let emojiLabel = UILabel()
        emojiLabel.text = emoji
        emojiLabel.font = UIFont.systemFont(ofSize: 14)
        stack.addArrangedSubview(emojiLabel)
        
        valueLabel.font = UIFont.boldSystemFont(ofSize: 15)
        valueLabel.textAlignment = .center
        stack.addArrangedSubview(valueLabel)
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 11)
        titleLabel.textColor = .gray
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)
        
        return stack
    }
    
    // MARK: - Config Card
    
    private func setupConfigCard() {
        styleCard(configCard)
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        configCard.addSubview(stack)
        pinToCard(stack, in: configCard)
        
        let titleLabel = UILabel()
        titleLabel.text = "⚙️ 测试参数"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        stack.addArrangedSubview(titleLabel)
        
        // Chunk size row
        let chunkRow = makeInputRow(
            title: "🧩 单次分配",
            unit: "MB",
            textField: chunkTextField,
            placeholder: "10"
        )
        stack.addArrangedSubview(chunkRow)
        
        let sep = UIView()
        sep.backgroundColor = UIColor(white: 0.85, alpha: 1)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(sep)
        
        // Hold time row
        let holdRow = makeInputRow(
            title: "⏱ 保持时间",
            unit: "ms",
            textField: holdTimeTextField,
            placeholder: "100"
        )
        stack.addArrangedSubview(holdRow)
        
        chunkTextField.text = "10"
        holdTimeTextField.text = "100"
        
        contentStack.addArrangedSubview(configCard)
    }
    
    private func makeInputRow(title: String, unit: String, textField: UITextField, placeholder: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 15)
        row.addArrangedSubview(label)
        
        let spacer = UIView()
        row.addArrangedSubview(spacer)
        
        textField.placeholder = placeholder
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.font = UIFont.systemFont(ofSize: 15)
        textField.borderStyle = .none
        textField.backgroundColor = .tertiarySystemGroupedBackground
        textField.layer.cornerRadius = 8
        textField.clipsToBounds = true
        // Add padding
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        textField.leftView = paddingView
        textField.leftViewMode = .always
        let rightPadding = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        textField.rightView = rightPadding
        textField.rightViewMode = .always
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 80),
            textField.heightAnchor.constraint(equalToConstant: 36),
        ])
        row.addArrangedSubview(textField)
        
        let unitLabel = UILabel()
        unitLabel.text = unit
        unitLabel.font = UIFont.systemFont(ofSize: 14)
        unitLabel.textColor = .gray
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        unitLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        row.addArrangedSubview(unitLabel)
        
        return row
    }
    
    // MARK: - Action Button
    
    private func setupActionButton() {
        actionButton.setTitle("▶  开始测试", for: .normal)
        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.backgroundColor = view.tintColor
        actionButton.layer.cornerRadius = 14
        actionButton.clipsToBounds = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.heightAnchor.constraint(equalToConstant: 54).isActive = true
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        
        // Shadow
        actionButton.layer.shadowColor = view.tintColor.cgColor
        actionButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        actionButton.layer.shadowRadius = 8
        actionButton.layer.shadowOpacity = 0.4
        actionButton.layer.masksToBounds = false
        
        contentStack.addArrangedSubview(actionButton)
    }
    
    // MARK: - Status Label
    
    private func setupStatusLabel() {
        statusLabel.text = "就绪"
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = .gray
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = .tertiarySystemGroupedBackground
        statusLabel.layer.cornerRadius = 16
        statusLabel.clipsToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        contentStack.addArrangedSubview(statusLabel)
    }
    
    // MARK: - Log Card
    
    private func setupLogCard() {
        styleCard(logCard)
        
        let outerStack = UIStackView()
        outerStack.axis = .vertical
        outerStack.spacing = 12
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(outerStack)
        pinToCard(outerStack, in: logCard)
        
        // Title row
        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        
        logTitleLabel.text = "📝 分配日志"
        logTitleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        titleRow.addArrangedSubview(logTitleLabel)
        
        let spacer = UIView()
        titleRow.addArrangedSubview(spacer)
        
        logCountLabel.text = "0 条"
        logCountLabel.font = UIFont.systemFont(ofSize: 12)
        logCountLabel.textColor = .gray
        titleRow.addArrangedSubview(logCountLabel)
        
        outerStack.addArrangedSubview(titleRow)
        
        logStack.axis = .vertical
        logStack.spacing = 4
        outerStack.addArrangedSubview(logStack)
        
        contentStack.addArrangedSubview(logCard)
    }
    
    // MARK: - Helpers
    
    private func styleCard(_ card: UIView) {
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.clipsToBounds = false
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 8
        card.layer.shadowOpacity = 0.06
    }
    
    private func pinToCard(_ stack: UIStackView, in card: UIView) {
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
    }
    
    private func memoryColor(for mb: Double) -> UIColor {
        if mb > 500 { return .red }
        if mb > 200 { return .orange }
        return UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
    }
    
    // MARK: - Actions
    
    @objc private func actionTapped() {
        if allocator.isRunning {
            allocator.stopTest()
            setRunningState(false)
        } else {
            let chunk = Double(chunkTextField.text ?? "10") ?? 10
            let hold = Double(holdTimeTextField.text ?? "100") ?? 100
            allocator.chunkSizeMB = max(1, chunk)
            allocator.holdTimeMS = max(10, hold)
            allocator.startTest()
            setRunningState(true)
        }
    }
    
    private func setRunningState(_ running: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.monitorCard.isHidden = !running
            self.monitorCard.alpha = running ? 1 : 0
            self.logCard.isHidden = !running
            self.logCard.alpha = running ? 1 : 0
            self.configCard.alpha = running ? 0.5 : 1.0
            self.contentStack.layoutIfNeeded()
        }
        
        chunkTextField.isEnabled = !running
        holdTimeTextField.isEnabled = !running
        
        if running {
            actionButton.setTitle("■  停止测试", for: .normal)
            actionButton.backgroundColor = .red
            actionButton.layer.shadowColor = UIColor.red.cgColor
            chunkStatLabel.text = "\(String(format: "%.0f", allocator.chunkSizeMB)) MB"
            intervalStatLabel.text = "\(String(format: "%.0f", allocator.holdTimeMS)) ms"
        } else {
            actionButton.setTitle("▶  开始测试", for: .normal)
            actionButton.backgroundColor = view.tintColor
            actionButton.layer.shadowColor = view.tintColor.cgColor
        }
        
        statusLabel.text = allocator.statusText
    }
    
    // MARK: - Crash Detection
    
    private func checkLastSession() {
        guard let session = logger.getLastSessionSummary(), session.wasOOM else {
            crashBannerView.isHidden = true
            return
        }
        
        crashBannerView.isHidden = false
        crashMemoryLabel.text = "💾 崩溃时内存: \(String(format: "%.1f", session.lastTotalMB)) MB"
        crashBlocksLabel.text = "📦 分配块数: \(session.lastBlockIndex) 块（每块 \(String(format: "%.0f", session.chunkMB)) MB）"
        crashIntervalLabel.text = "⏱ 保持间隔: \(String(format: "%.0f", session.holdTimeMS)) ms"
        crashTimeLabel.text = "📅 崩溃时间: \(logger.formatDate(session.endTime))"
    }
    
    // MARK: - Update Log Display
    
    private func updateLogDisplay() {
        let records = allocator.allocationHistory.suffix(20).reversed()
        
        // Remove old rows
        for sub in logStack.arrangedSubviews {
            logStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        
        for record in records {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            
            let indexLabel = UILabel()
            indexLabel.text = "#\(record.blockIndex)"
            indexLabel.font = UIFont(name: "Menlo", size: 12) ?? UIFont.systemFont(ofSize: 12)
            indexLabel.textColor = .gray
            indexLabel.translatesAutoresizingMaskIntoConstraints = false
            indexLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
            row.addArrangedSubview(indexLabel)
            
            // Progress bar
            let progressBg = UIView()
            progressBg.backgroundColor = UIColor(white: 0.9, alpha: 1)
            progressBg.layer.cornerRadius = 3
            progressBg.clipsToBounds = true
            progressBg.translatesAutoresizingMaskIntoConstraints = false
            progressBg.heightAnchor.constraint(equalToConstant: 6).isActive = true
            
            let progressFill = UIView()
            progressFill.backgroundColor = memoryColor(for: record.totalMB)
            progressFill.layer.cornerRadius = 3
            progressFill.translatesAutoresizingMaskIntoConstraints = false
            progressBg.addSubview(progressFill)
            
            let fraction = CGFloat(min(record.totalMB / 1024.0, 1.0))
            NSLayoutConstraint.activate([
                progressFill.topAnchor.constraint(equalTo: progressBg.topAnchor),
                progressFill.bottomAnchor.constraint(equalTo: progressBg.bottomAnchor),
                progressFill.leadingAnchor.constraint(equalTo: progressBg.leadingAnchor),
                progressFill.widthAnchor.constraint(equalTo: progressBg.widthAnchor, multiplier: max(fraction, 0.02)),
            ])
            
            row.addArrangedSubview(progressBg)
            
            let valueLabel = UILabel()
            valueLabel.text = "\(String(format: "%.1f", record.totalMB)) MB"
            valueLabel.font = UIFont(name: "Menlo-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12)
            valueLabel.textAlignment = .right
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            valueLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
            row.addArrangedSubview(valueLabel)
            
            logStack.addArrangedSubview(row)
        }
        
        logCountLabel.text = "最近 \(allocator.allocationHistory.count) 条"
    }
}

// MARK: - MemoryAllocatorDelegate

extension MainViewController: MemoryAllocatorDelegate {
    
    func allocatorDidUpdate(allocatedMB: Double, blockCount: Int, statusText: String) {
        memoryValueLabel.text = String(format: "%.1f", allocatedMB)
        memoryValueLabel.textColor = memoryColor(for: allocatedMB)
        blocksStatLabel.text = "\(blockCount)"
        self.statusLabel.text = statusText
        
        updateLogDisplay()
    }
    
    func allocatorDidFinish() {
        setRunningState(false)
        checkLastSession()
    }
}
