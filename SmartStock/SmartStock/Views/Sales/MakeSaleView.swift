//
//  MakeSaleView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
 
import SwiftUI
import Supabase
 
 
 
struct MakeSaleView: View {
    private enum CartOverrideAction {
        case itemPrice(itemId: UUID, newPrice: Double)
        case itemDiscount(itemId: UUID, newDiscount: Double)
    }

    private enum SalePaymentMethod: String, CaseIterable, Identifiable {
        case cash = "CASH"
        case card = "CARD"
        case cheque = "CHEQUE"
        case account = "ACCOUNT"
 
        var id: String { rawValue }
 
        var title: String {
            switch self {
            case .cash: return "Cash"
            case .card: return "Card"
            case .cheque: return "Cheque"
            case .account: return "Account Credit"
            }
        }
 
        var checkoutMethod: CheckoutPaymentMethod {
            switch self {
            case .cash: return .cash
            case .card: return .card
            case .cheque: return .cheque
            case .account: return .account
            }
        }
    }
 
    @EnvironmentObject var sessionManager: SessionManager
 
    @State private var searchText = ""
    @State private var products: [Product] = []
    @State private var cart: [CartItem] = []
    @State private var paymentMethod: SalePaymentMethod = .cash
    @State private var customerAccounts: [CustomerAccount] = []
    @State private var selectedCustomerAccountId: Int?
    @State private var cashCollectedText = ""
    @State private var paymentReferenceText = ""
    @State private var isShowingCheckoutSheet = false
    @State private var isCheckingOut = false
    @State private var checkoutMessage: String?
    @State private var checkoutError: String?
    @State private var lastReceiptPayload: ReceiptPrintPayload?
    @State private var isShowingScanner = false
    @State private var scannedBarcode = ""
    @State private var scannerError: String?
    @State private var editingPriceItemID: UUID?
    @State private var editedUnitPriceText = ""
    @State private var editingDiscountItemID: UUID?
    @State private var editedItemDiscountText = ""
    @State private var pendingOverrideAction: CartOverrideAction?
    @State private var overrideApproverIdentifier = ""
    @State private var overrideApproverPassword = ""
    @State private var overrideReason = ""
    @State private var overrideErrorMessage: String?
    @State private var isApprovingOverride = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    private let overrideApprovalService = OverrideApprovalService()
 
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
 
                // 🔍 Search Bar + Overlay Results
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
 
                            TextField("Product Lookup", text: $searchText)
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
 
                            Rectangle()
                                .fill(.white.opacity(0.28))
                                .frame(width: 1, height: 30)
 
                            Button {
                                checkoutError = nil
                                checkoutMessage = nil
                                scannerError = nil
                                isShowingScanner = true
                            } label: {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.title2.weight(.semibold))
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.16))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scan barcode")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 58)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.55), .white.opacity(0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.black.opacity(0.68), lineWidth: 2.2)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
 
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
                                        HStack(spacing: 12) {
                                            // ✅ Product image (exactly like the cart)
                                            cartItemImage(for: product)
                                                .frame(width: 48, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
 
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(product.displayName)
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
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.systemBackground))
                                        .contentShape(Rectangle())
                                    }
 
                                    if product.id != products.last?.id {
                                        Divider()
                                            .padding(.leading, 74)   // indent past the image
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 230)          // increased from 176 to fit taller rows with images
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .offset(y: scannerError == nil ? 62 : 84)
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
                .frame(height: scannerError == nil ? 96 : 118)
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
                                                    cartItemImage(for: item.product)
                                                        .frame(width: 54, height: 54)
                                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                 
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(item.product.displayName)
                                                            .font(.headline)
                                                            .lineLimit(2)
                 
                                                        Text("ID: \(item.product.id)")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                 
                                                        if item.discountAmount > 0 {
                                                            Text("Item discount: -$\(item.discountAmount, specifier: "%.2f")")
                                                                .font(.caption)
                                                                .foregroundColor(.orange)
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
                                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                                    Button("Discount") {
                                                        editingDiscountItemID = item.id
                                                        editedItemDiscountText = String(format: "%.2f", item.discountAmount)
                                                    }
                                                    .tint(.orange)
 
                                                    Button("Price") {
                                                        editingPriceItemID = item.id
                                                        editedUnitPriceText = String(format: "%.2f", item.unitPrice)
                                                    }
                                                    .tint(.blue)
                                                }
                                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                    Button(role: .destructive) {
                                                        removeCartItem(item)
                                                    } label: {
                                                        Text("Delete")
                                                    }
                                                }
                                            }
                                            .onDelete(perform: removeFromCart)
                                        }
                                        .listStyle(.plain)
                                        .listRowSpacing(6)
                                        .contentMargins(.top, 12, for: .scrollContent)
                                    }
                 
                                    Divider()
                 
                                    VStack {
                                        HStack(spacing: 16) {
                                            Text("Subtotal: $\(subtotal, specifier: "%.2f")")
                                                .font(.subheadline)
                 
                                            Text("Total: $\(total, specifier: "%.2f")")
                                                .font(.headline)
                                        }
                 
                                        if itemDiscountTotal > 0 {
                                            Text("Item Discounts: -$\(itemDiscountTotal, specifier: "%.2f")")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                 
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

                                        if lastReceiptPayload != nil {
                                            HStack(spacing: 10) {
                                                Button {
                                                    Task { await printLastReceipt(format: .letter) }
                                                } label: {
                                                    Label("Letter", systemImage: "doc.text")
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(.bordered)

                                                Button {
                                                    Task { await printLastReceipt(format: .fortyColumn) }
                                                } label: {
                                                    Label("40-Col", systemImage: "printer")
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
 
                                        Button {
                                            checkoutError = nil
                                            checkoutMessage = nil
                                            lastReceiptPayload = nil
                                            isShowingCheckoutSheet = true
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
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Text("Make Sale")
                                        .font(.title2.weight(.semibold))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isSearchFieldFocused = false
                            }
                            .alert("Change Item Price", isPresented: isEditingItemPrice) {
                                TextField("Unit price", text: $editedUnitPriceText)
                                    .keyboardType(.decimalPad)
                                Button("Cancel", role: .cancel) {
                                    editingPriceItemID = nil
                                }
                                Button("Save") {
                                    guard let itemID = editingPriceItemID else { return }
                                    Task { await applyEditedPrice(for: itemID) }
                                }
                            } message: {
                                Text("Update the unit price for this cart item.")
                            }
                            .alert("Item Discount", isPresented: isEditingItemDiscount) {
                                TextField("Discount amount", text: $editedItemDiscountText)
                                    .keyboardType(.decimalPad)
                                Button("Cancel", role: .cancel) {
                                    editingDiscountItemID = nil
                                }
                                Button("Save") {
                                    guard let itemID = editingDiscountItemID else { return }
                                    Task { await applyEditedItemDiscount(for: itemID) }
                                }
                            } message: {
                                Text("Apply a discount to this cart line.")
                            }
                            .onDisappear {
                                searchTask?.cancel()
                            }
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                VStack(spacing: 6) {
                                    Spacer()
                                        .frame(height: 18)
                 
                                    Button("Clear Cart") {
                                        clearCart()
                                    }
                                    .font(.headline)
                                    .foregroundColor(.red)
                                    .disabled(cart.isEmpty || isCheckingOut)
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemBackground))
                            }
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                            .sheet(isPresented: $isShowingCheckoutSheet) {
                                checkoutSheet
                            }
                            .sheet(isPresented: isShowingOverrideSheet) {
                                overrideSheet
                            }
                            .onChange(of: paymentMethod) { _, newMethod in
                                if newMethod == .cash {
                                    cashCollectedText = String(format: "%.2f", total)
                                }
                                if newMethod == .cash || newMethod == .account {
                                    paymentReferenceText = ""
                                }
                            }
                            .task {
                                await loadCustomerAccounts()
                            }
                        }
                    }

    var canApplySaleDiscount: Bool {
        sessionManager.currentUser?.canAccess(.applySaleDiscount) == true
    }

    var canChangeSaleItemPrice: Bool {
        sessionManager.currentUser?.canAccess(.changeSaleItemPrice) == true
    }

    var subtotal: Double {
        cart.reduce(0) { $0 + $1.subtotal }
    }

    var discountedCartSubtotal: Double {
        cart.reduce(0) { $0 + $1.lineTotal }
    }

    var total: Double {
        max(discountedCartSubtotal, 0)
    }

    var itemDiscountTotal: Double {
        cart.reduce(0) { $0 + $1.discountAmount }
    }

    var selectedCustomer: CustomerAccount? {
        guard let selectedCustomerAccountId else { return nil }
        return customerAccounts.first(where: { $0.customerId == selectedCustomerAccountId })
    }

    var cashCollectedAmount: Double? {
        Double(cashCollectedText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var changeDue: Double {
        max((cashCollectedAmount ?? 0) - total, 0)
    }

    var cashStillOwed: Double {
        max(total - (cashCollectedAmount ?? 0), 0)
    }

    var isEditingItemPrice: Binding<Bool> {
        Binding {
            editingPriceItemID != nil
        } set: { isPresented in
            if !isPresented {
                editingPriceItemID = nil
            }
        }
    }

    var isEditingItemDiscount: Binding<Bool> {
        Binding {
            editingDiscountItemID != nil
        } set: { isPresented in
            if !isPresented {
                editingDiscountItemID = nil
            }
        }
    }

    var isShowingOverrideSheet: Binding<Bool> {
        Binding {
            pendingOverrideAction != nil
        } set: { isPresented in
            if !isPresented {
                pendingOverrideAction = nil
                overrideErrorMessage = nil
            }
        }
    }

    var isShowingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !products.isEmpty
    }

    func addToCart(_ product: Product) {
        checkoutError = nil
        checkoutMessage = nil
        lastReceiptPayload = nil
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
        cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
    }

    func decreaseQuantity(for item: CartItem) {
        checkoutError = nil
        checkoutMessage = nil

        guard let index = cart.firstIndex(where: { $0.id == item.id }) else { return }

        if cart[index].quantity > 1 {
            cart[index].quantity -= 1
            cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
        } else {
            cart.remove(at: index)
        }
    }

    func removeFromCart(at offsets: IndexSet) {
        checkoutError = nil
        checkoutMessage = nil
        cart.remove(atOffsets: offsets)
    }

    func removeCartItem(_ item: CartItem) {
        checkoutError = nil
        checkoutMessage = nil
        guard let index = cart.firstIndex(where: { $0.id == item.id }) else { return }
        cart.remove(at: index)
    }

    func clearCart() {
        checkoutError = nil
        checkoutMessage = nil
        lastReceiptPayload = nil
        scannerError = nil
        products = []
        cart.removeAll()
        paymentMethod = .cash
        selectedCustomerAccountId = nil
        cashCollectedText = ""
        paymentReferenceText = ""
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
                .select("product_id, name, size, sku, price, image_url")
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
                .select("product_id, name, size, sku, price, image_url")
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
                .select("product_id, name, size, sku, price, image_url")
                .or("name.ilike.%\(trimmedSearch)%,size.ilike.%\(trimmedSearch)%,sku.ilike.%\(trimmedSearch)%,barcode.ilike.%\(trimmedSearch)%")
                .limit(4)
                .execute()
                .value

            if Task.isCancelled { return }

            if !results.isEmpty {
                await MainActor.run {
                    products = results
                }
                return
            }

            struct BarcodeMatch: Decodable {
                let product_id: Int
            }

            let barcodeResults: [BarcodeMatch] = try await supabase
                .from("product_barcodes")
                .select("product_id")
                .eq("barcode", value: trimmedSearch)
                .limit(1)
                .execute()
                .value

            guard let match = barcodeResults.first else {
                await MainActor.run {
                    products = []
                }
                return
            }

            let matchedProducts: [Product] = try await supabase
                .from("products")
                .select("product_id, name, size, sku, price, image_url")
                .eq("product_id", value: match.product_id)
                .limit(1)
                .execute()
                .value

            if Task.isCancelled { return }

            await MainActor.run {
                products = matchedProducts
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

        if paymentMethod == .account, selectedCustomerAccountId == nil {
            checkoutError = "Select a customer account for account billing."
            return
        }

        if paymentMethod == .cash, (cashCollectedAmount ?? 0) < total {
            checkoutError = "Cash collected must be at least the sale total."
            return
        }

        if requiresPaymentReference && trimmedPaymentReference.isEmpty {
            checkoutError = paymentMethod == .card ? "Enter the card transaction ID." : "Enter the cheque number."
            return
        }

        isCheckingOut = true
        checkoutError = nil
        checkoutMessage = nil
        defer { isCheckingOut = false }

        do {
            let receiptPayload = try await CheckoutService.checkout(
                cart: cart,
                user: user,
                store: store,
                paymentMethod: paymentMethod.checkoutMethod,
                customerAccountId: selectedCustomerAccountId,
                paymentReference: trimmedPaymentReference,
                device: sessionManager.currentDevice
            )
            if let receiptPayload {
                lastReceiptPayload = ReceiptPrintPayload(
                    saleId: receiptPayload.saleId,
                    receiptNumber: receiptPayload.receiptNumber,
                    date: receiptPayload.date,
                    cashierName: receiptPayload.cashierName,
                    deviceId: receiptPayload.deviceId,
                    customerName: receiptPayload.customerName,
                    storeName: receiptPayload.storeName,
                    paymentMethod: receiptPayload.paymentMethod,
                    paymentStatus: receiptPayload.paymentStatus,
                    amountPaid: receiptPayload.amountPaid,
                    cashCollected: paymentMethod == .cash ? cashCollectedAmount : nil,
                    changeDue: paymentMethod == .cash ? changeDue : nil,
                    subtotal: receiptPayload.subtotal,
                    discountAmount: receiptPayload.discountAmount,
                    total: receiptPayload.total,
                    items: receiptPayload.items
                )
            } else {
                lastReceiptPayload = nil
            }

            cart.removeAll()
            products = []
            searchText = ""
            scannedBarcode = ""
            scannerError = nil
            paymentMethod = .cash
            selectedCustomerAccountId = nil
            cashCollectedText = ""
            paymentReferenceText = ""
            isShowingCheckoutSheet = false
            isSearchFieldFocused = true
            checkoutMessage = "Sale completed successfully."
        } catch {
            checkoutError = error.localizedDescription
            print("CHECKOUT ERROR:", error)
        }
    }

    func printLastReceipt(format: ReceiptPrintFormat) async {
        guard let lastReceiptPayload, let store = sessionManager.selectedStore else { return }

        do {
            let preferences = try await CustomOrderService().fetchCompanyPreferences(locationId: store.id)
            ReceiptPrintingService.printReceipt(
                payload: lastReceiptPayload,
                preferences: preferences,
                format: format
            )
        } catch {
            checkoutError = error.localizedDescription
        }
    }

    func loadCustomerAccounts() async {
        do {
            customerAccounts = try await CustomerAccountService.fetchCustomers()
        } catch {
            print("LOAD SALE CUSTOMER ACCOUNTS ERROR:", error)
        }
    }

    func applyEditedPrice(for itemID: UUID) async {
        guard let index = cart.firstIndex(where: { $0.id == itemID }) else {
            self.editingPriceItemID = nil
            return
        }

        guard let newPrice = parsedMoneyValue(editedUnitPriceText),
              newPrice >= 0 else {
            checkoutError = "Enter a valid unit price."
            return
        }

        if !canChangeSaleItemPrice {
            pendingOverrideAction = .itemPrice(itemId: itemID, newPrice: newPrice)
            overrideApproverIdentifier = ""
            overrideApproverPassword = ""
            overrideReason = ""
            overrideErrorMessage = nil
            self.editingPriceItemID = nil
            return
        }

        cart[index].unitPrice = newPrice
        cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
        checkoutError = nil
        self.editingPriceItemID = nil
    }

    func applyEditedItemDiscount(for itemID: UUID) async {
        guard let index = cart.firstIndex(where: { $0.id == itemID }) else {
            self.editingDiscountItemID = nil
            return
        }

        guard let newDiscount = parsedMoneyValue(editedItemDiscountText),
              newDiscount >= 0 else {
            checkoutError = "Enter a valid item discount."
            return
        }

        if !canApplySaleDiscount {
            pendingOverrideAction = .itemDiscount(itemId: itemID, newDiscount: newDiscount)
            overrideApproverIdentifier = ""
            overrideApproverPassword = ""
            overrideReason = ""
            overrideErrorMessage = nil
            self.editingDiscountItemID = nil
            return
        }

        cart[index].discountAmount = min(newDiscount, cart[index].subtotal)
        checkoutError = nil
        self.editingDiscountItemID = nil
    }

    private func parsedMoneyValue(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        return Double(normalized)
    }

    private func applyPendingOverrideAction() {
        guard let pendingOverrideAction else { return }
        switch pendingOverrideAction {
        case .itemPrice(let itemId, let newPrice):
            guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
            cart[index].unitPrice = newPrice
            cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
        case .itemDiscount(let itemId, let newDiscount):
            guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
            cart[index].discountAmount = min(newDiscount, cart[index].subtotal)
        }
    }

    private func requestOverrideApproval() async {
        let trimmedIdentifier = overrideApproverIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = overrideApproverPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = overrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            overrideErrorMessage = "Override reason is required."
            return
        }

        guard let requiredPermission = requiredPermissionForPendingAction else {
            overrideErrorMessage = "No override action pending."
            return
        }

        isApprovingOverride = true
        defer { isApprovingOverride = false }

        do {
            _ = try await overrideApprovalService.validateApprover(
                identifier: trimmedIdentifier,
                password: trimmedPassword,
                requiredPermission: requiredPermission
            )
            applyPendingOverrideAction()
            pendingOverrideAction = nil
            overrideErrorMessage = nil
            checkoutError = nil
        } catch {
            overrideErrorMessage = error.localizedDescription
        }
    }

    private var requiredPermissionForPendingAction: MobilePermission? {
        guard let pendingOverrideAction else { return nil }
        switch pendingOverrideAction {
        case .itemPrice:
            return .changeSaleItemPrice
        case .itemDiscount:
            return .applySaleDiscount
        }
    }

    private var overrideSheet: some View {
        NavigationStack {
            Form {
                if let overrideErrorMessage {
                    Section {
                        Text(overrideErrorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Override Required") {
                    Text("This change needs manager approval.")
                        .font(.subheadline)
                    TextField("Approver username/email/badge", text: $overrideApproverIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("Approver password", text: $overrideApproverPassword)
                    TextField("Override reason", text: $overrideReason, axis: .vertical)
                }
            }
            .navigationTitle("Approval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pendingOverrideAction = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await requestOverrideApproval() }
                    } label: {
                        if isApprovingOverride {
                            ProgressView()
                        } else {
                            Text("Approve")
                        }
                    }
                    .disabled(isApprovingOverride)
                }
            }
        }
    }

    private var checkoutSheet: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(SalePaymentMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if paymentMethod == .cash {
                    Section("Cash Collected") {
                        TextField("Cash received", text: $cashCollectedText)
                            .keyboardType(.decimalPad)

                        LabeledContent("Total Due", value: String(format: "$%.2f", total))

                        if cashStillOwed > 0 {
                            LabeledContent("Still Owed", value: String(format: "$%.2f", cashStillOwed))
                                .foregroundStyle(.red)
                        } else {
                            LabeledContent("Change Due", value: String(format: "$%.2f", changeDue))
                        }
                    }
                }

                if requiresPaymentReference {
                    Section(paymentReferenceSectionTitle) {
                        TextField(paymentReferencePlaceholder, text: $paymentReferenceText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)

                        Text(paymentMethod == .card ? "This stores the processor transaction ID for lookup later." : "This stores the cheque number for the sale.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(paymentMethod == .account ? "Customer Account" : "Customer Account (Optional)") {
                    Picker("Customer", selection: $selectedCustomerAccountId) {
                        Text(paymentMethod == .account ? "Select customer" : "No customer").tag(Int?.none)
                        ForEach(customerAccounts.filter(\.isActive)) { customer in
                            Text(customer.name).tag(Int?.some(customer.customerId))
                        }
                    }

                    if let selectedCustomer = selectedCustomer {
                        LabeledContent("Current Balance", value: selectedCustomer.balanceText)
                        LabeledContent("Credit Limit", value: selectedCustomer.creditLimitText)
                    }
                }

                Section("Sale Summary") {
                    LabeledContent("Subtotal", value: String(format: "$%.2f", subtotal))
                    if itemDiscountTotal > 0 {
                        LabeledContent("Item Discounts", value: String(format: "-$%.2f", itemDiscountTotal))
                    }
                    LabeledContent("Total", value: String(format: "$%.2f", total))
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingCheckoutSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete Sale") {
                        Task {
                            await checkout()
                        }
                    }
                    .disabled(
                        isCheckingOut
                        || (paymentMethod == .account && selectedCustomerAccountId == nil)
                        || (paymentMethod == .cash && (cashCollectedAmount ?? 0) < total)
                        || (requiresPaymentReference && trimmedPaymentReference.isEmpty)
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if cashCollectedText.isEmpty {
                cashCollectedText = String(format: "%.2f", total)
            }
        }
    }

    @ViewBuilder
    private func cartItemImage(for product: Product) -> some View {
        if let imageURL = product.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    cartItemImagePlaceholder
                }
            }
        } else {
            cartItemImagePlaceholder
        }
    }

    private var cartItemImagePlaceholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.secondary)
        }
    }

    private var requiresPaymentReference: Bool {
        paymentMethod == .card || paymentMethod == .cheque
    }

    private var trimmedPaymentReference: String {
        paymentReferenceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var paymentReferenceSectionTitle: String {
        paymentMethod == .card ? "Card Transaction" : "Cheque Details"
    }

    private var paymentReferencePlaceholder: String {
        paymentMethod == .card ? "Transaction ID" : "Cheque number"
    }
}
