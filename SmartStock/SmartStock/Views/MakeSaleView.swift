//
//  MakeSaleView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI
import Supabase
import AVFoundation



struct MakeSaleView: View {
    @EnvironmentObject var sessionManager: SessionManager

    @State private var searchText = ""
    @State private var products: [Product] = []
    @State private var cart: [CartItem] = []
    @State private var isCheckingOut = false
    @State private var checkoutMessage: String?
    @State private var checkoutError: String?
    @State private var isShowingScanner = false
    @State private var scannedBarcode = ""
    @State private var scannerError: String?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // 🔍 Search Bar + Overlay Results
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            TextField("Search product...", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isSearchFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(.search)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isSearchFieldFocused = true
                                    }
                                }
                                .onChange(of: searchText) {
                                    scheduleSearch()
                                }

                            Button {
                                checkoutError = nil
                                checkoutMessage = nil
                                scannerError = nil
                                isShowingScanner = true
                            } label: {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.bordered)
                        }

                        if let scannerError {
                            Text(scannerError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }

                    if isShowingSearchResults {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(products) { product in
                                    Button {
                                        addToCart(product)
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(product.name)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)

                                                if let price = product.price {
                                                    Text("Price: $\(price, specifier: "%.2f")")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }

                                                if let sku = product.sku, !sku.isEmpty {
                                                    Text("SKU: \(sku)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            Image(systemName: "plus.circle.fill")
                                                .font(.title3)
                                                .foregroundColor(.accentColor)
                                                .padding(.top, 2)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                                        .background(Color(.systemBackground))
                                        .contentShape(Rectangle())
                                    }

                                    if product.id != products.last?.id {
                                        Divider()
                                            .padding(.leading)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .offset(y: scannerError == nil ? 50 : 72)
                        .shadow(radius: 4)
                    }
                }
                .sheet(isPresented: $isShowingScanner) {
                    BarcodeScannerSheet(
                        scannedCode: $scannedBarcode,
                        isPresented: $isShowingScanner,
                        onScanned: { code in
                            Task {
                                await handleScannedBarcode(code)
                            }
                        }
                    )
                }
                .padding([.horizontal, .top])
                .frame(height: scannerError == nil ? 100 : 124)
                .zIndex(1)

                VStack(spacing: 0) {
                    if cart.isEmpty {
                        Spacer()

                        VStack(spacing: 10) {
                            Image(systemName: "cart")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)

                            Text("Cart is empty")
                                .font(.headline)

                            Text("Search for a product to add it to the sale.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()

                        Spacer()
                    } else {
                        List {
                            ForEach(cart) { item in
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.product.name)
                                            .font(.headline)

                                        if let price = item.product.price {
                                            Text("$\(price, specifier: "%.2f") each")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Button {
                                            decreaseQuantity(for: item)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)

                                        Text("\(item.quantity)")
                                            .frame(minWidth: 24)

                                        Button {
                                            increaseQuantity(for: item)
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Text("$\(item.lineTotal, specifier: "%.2f")")
                                        .font(.headline)
                                        .frame(minWidth: 70, alignment: .trailing)
                                }
                                .padding(.vertical, 2)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onDelete(perform: removeFromCart)
                        }
                        .listStyle(.plain)
                        .listRowSpacing(6)
                        .contentMargins(.top, 12, for: .scrollContent)
                    }

                    Divider()

                    VStack {
                        Text("Total: $\(total, specifier: "%.2f")")
                            .font(.headline)

                        if let checkoutError {
                            Text(checkoutError)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }

                        if let checkoutMessage {
                            Text(checkoutMessage)
                                .foregroundColor(.green)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }

                        Button("Clear Cart") {
                            clearCart()
                        }
                        .foregroundColor(.red)
                        .disabled(cart.isEmpty || isCheckingOut)

                        Button {
                            Task {
                                await checkout()
                            }
                        } label: {
                            if isCheckingOut {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Checkout")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(cart.isEmpty || isCheckingOut)
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Make Sale")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    var total: Double {
        cart.reduce(0) { $0 + $1.lineTotal }
    }

    var isShowingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !products.isEmpty
    }

    func addToCart(_ product: Product) {
        checkoutError = nil
        checkoutMessage = nil
        searchText = ""
        products = []
        scannedBarcode = ""
        scannerError = nil
        isSearchFieldFocused = true
        if let index = cart.firstIndex(where: { $0.product.id == product.id }) {
            cart[index].quantity += 1
        } else {
            cart.append(CartItem(product: product, quantity: 1))
        }
    }

    func increaseQuantity(for item: CartItem) {
        checkoutError = nil
        checkoutMessage = nil

        guard let index = cart.firstIndex(where: { $0.id == item.id }) else { return }
        cart[index].quantity += 1
    }

    func decreaseQuantity(for item: CartItem) {
        checkoutError = nil
        checkoutMessage = nil

        guard let index = cart.firstIndex(where: { $0.id == item.id }) else { return }

        if cart[index].quantity > 1 {
            cart[index].quantity -= 1
        } else {
            cart.remove(at: index)
        }
    }

    func removeFromCart(at offsets: IndexSet) {
        checkoutError = nil
        checkoutMessage = nil
        cart.remove(atOffsets: offsets)
    }

    func clearCart() {
        checkoutError = nil
        checkoutMessage = nil
        scannerError = nil
        products = []
        cart.removeAll()
        isSearchFieldFocused = true
    }
    func handleScannedBarcode(_ code: String) async {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }

        await MainActor.run {
            scannedBarcode = trimmedCode
            searchText = trimmedCode
            products = []
            checkoutError = nil
            checkoutMessage = nil
            scannerError = nil
        }

        await searchProductByBarcode(trimmedCode)
    }

    func searchProductByBarcode(_ barcode: String) async {
        do {
            // 1️⃣ Try direct match in products table
            let directResults: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .or("barcode.eq.\(barcode),sku.eq.\(barcode)")
                .limit(1)
                .execute()
                .value

            if let product = directResults.first {
                await MainActor.run {
                    addToCart(product)
                }
                return
            }

            // 2️⃣ Try lookup in product_barcodes table
            struct BarcodeMatch: Decodable {
                let product_id: Int
            }

            let barcodeResults: [BarcodeMatch] = try await supabase
                .from("product_barcodes")
                .select("product_id")
                .eq("barcode", value: barcode)
                .limit(1)
                .execute()
                .value

            guard let match = barcodeResults.first else {
                await MainActor.run {
                    scannerError = "No product found for barcode: \(barcode)"
                    isSearchFieldFocused = true
                }
                return
            }

            // 3️⃣ Fetch actual product using product_id
            let products: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .eq("product_id", value: match.product_id)
                .limit(1)
                .execute()
                .value

            await MainActor.run {
                if let product = products.first {
                    addToCart(product)
                } else {
                    scannerError = "Product exists but could not be loaded."
                }
            }

        } catch {
            await MainActor.run {
                scannerError = "Unable to scan product right now."
                isSearchFieldFocused = true
            }
            print("BARCODE SEARCH ERROR:", error)
        }
    }

    func searchProducts() async {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        checkoutError = nil
        guard !trimmedSearch.isEmpty else {
            products = []
            return
        }

        do {
            let results: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .ilike("name", pattern: "%\(trimmedSearch)%")
                .limit(4)
                .execute()
                .value

            if Task.isCancelled { return }

            await MainActor.run {
                products = results
            }
        } catch {
            if Task.isCancelled { return }
            print("SEARCH ERROR:", error)
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            products = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await searchProducts()
        }
    }

    func checkout() async {
        guard let user = sessionManager.currentUser,
              let store = sessionManager.selectedStore,
              !cart.isEmpty else { return }

        isCheckingOut = true
        checkoutError = nil
        checkoutMessage = nil
        defer { isCheckingOut = false }

        do {
            try await CheckoutService.checkout(
                cart: cart,
                user: user,
                store: store
            )

            cart.removeAll()
            products = []
            searchText = ""
            scannedBarcode = ""
            scannerError = nil
            isSearchFieldFocused = true
            checkoutMessage = "Sale completed successfully."
        } catch {
            checkoutError = error.localizedDescription
            print("CHECKOUT ERROR:", error)
        }
    }
}

struct BarcodeScannerSheet: View {
    @Binding var scannedCode: String
    @Binding var isPresented: Bool
    let onScanned: (String) -> Void

    var body: some View {
        NavigationStack {
            BarcodeScannerRepresentable { code in
                scannedCode = code
                isPresented = false
                onScanned(code)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        let onScanned: (String) -> Void
        private var hasScanned = false

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func scannerViewController(_ controller: ScannerViewController, didScan code: String) {
            guard !hasScanned else { return }
            hasScanned = true
            onScanned(code)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func scannerViewController(_ controller: ScannerViewController, didScan code: String)
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFinishScanning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkCameraPermissionAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func checkCameraPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configureScanner()
                    } else {
                        self.showPermissionDeniedMessage()
                    }
                }
            }
        default:
            showPermissionDeniedMessage()
        }
    }

    private func configureScanner() {
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            showScannerUnavailableMessage()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showScannerUnavailableMessage()
            return
        }

        session.beginConfiguration()
        session.addInput(videoInput)
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .code128, .qr, .upce]
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        let label = UILabel()
        label.text = "Align the barcode inside the frame"
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            label.heightAnchor.constraint(equalToConstant: 44)
        ])

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    private func showPermissionDeniedMessage() {
        let label = UILabel()
        label.text = "Camera access is required to scan barcodes. Enable it in Settings."
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func showScannerUnavailableMessage() {
        let label = UILabel()
        label.text = "Barcode scanner is unavailable on this device."
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didFinishScanning,
              let firstObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = firstObject.stringValue else { return }

        didFinishScanning = true
        session.stopRunning()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        delegate?.scannerViewController(self, didScan: code)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }
}
