//
//  MakeSaleView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI
import Supabase



struct MakeSaleView: View {
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
    @State private var isShowingCheckoutSheet = false
    @State private var isCheckingOut = false
    @State private var checkoutMessage: String?
    @State private var checkoutError: String?
    @State private var isShowingScanner = false
    @State private var scannedBarcode = ""
    @State private var scannerError: String?
    @State private var editingPriceItemID: UUID?
    @State private var editedUnitPriceText = ""
    @State private var editingDiscountItemID: UUID?
    @State private var editedItemDiscountText = ""
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

                                        if item.discountAmount > 0 {
                                            Text("Item discount: -$\(item.discountAmount, specifier: "%.2f")")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }

                                        Text("$\(item.unitPrice, specifier: "%.2f") each")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canApplySaleDiscount {
                                        Button("Discount") {
                                            editingDiscountItemID = item.id
                                            editedItemDiscountText = String(format: "%.2f", item.discountAmount)
                                        }
                                        .tint(.orange)
                                    }

                                    if canChangeSaleItemPrice {
                                        Button("Price") {
                                            editingPriceItemID = item.id
                                            editedUnitPriceText = String(format: "%.2f", item.unitPrice)
                                        }
                                        .tint(.blue)
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

                        Button {
                            checkoutError = nil
                            checkoutMessage = nil
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
            .navigationTitle("Make Sale")
            .navigationBarTitleDisplayMode(.inline)
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
                    applyEditedPrice()
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
                    applyEditedItemDiscount()
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
            .onChange(of: paymentMethod) { _, newMethod in
                if newMethod == .cash {
                    cashCollectedText = String(format: "%.2f", total)
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

    func clearCart() {
        checkoutError = nil
        checkoutMessage = nil
        scannerError = nil
        products = []
        cart.removeAll()
        paymentMethod = .cash
        selectedCustomerAccountId = nil
        cashCollectedText = ""
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
                .or("name.ilike.%\(trimmedSearch)%,sku.ilike.%\(trimmedSearch)%,barcode.ilike.%\(trimmedSearch)%")
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
                .select("product_id, name, sku, price")
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

        isCheckingOut = true
        checkoutError = nil
        checkoutMessage = nil
        defer { isCheckingOut = false }

        do {
            try await CheckoutService.checkout(
                cart: cart,
                user: user,
                store: store,
                paymentMethod: paymentMethod.checkoutMethod,
                customerAccountId: selectedCustomerAccountId
            )

            cart.removeAll()
            products = []
            searchText = ""
            scannedBarcode = ""
            scannerError = nil
            paymentMethod = .cash
            selectedCustomerAccountId = nil
            cashCollectedText = ""
            isShowingCheckoutSheet = false
            isSearchFieldFocused = true
            checkoutMessage = "Sale completed successfully."
        } catch {
            checkoutError = error.localizedDescription
            print("CHECKOUT ERROR:", error)
        }
    }

    func loadCustomerAccounts() async {
        do {
            customerAccounts = try await supabase
                .from("customer_accounts")
                .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            print("LOAD SALE CUSTOMER ACCOUNTS ERROR:", error)
        }
    }

    func applyEditedPrice() {
        guard let editingPriceItemID,
              let index = cart.firstIndex(where: { $0.id == editingPriceItemID }) else {
            self.editingPriceItemID = nil
            return
        }

        guard let newPrice = Double(editedUnitPriceText.trimmingCharacters(in: .whitespacesAndNewlines)),
              newPrice >= 0 else {
            checkoutError = "Enter a valid unit price."
            return
        }

        cart[index].unitPrice = newPrice
        cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
        self.editingPriceItemID = nil
    }

    func applyEditedItemDiscount() {
        guard let editingDiscountItemID,
              let index = cart.firstIndex(where: { $0.id == editingDiscountItemID }) else {
            self.editingDiscountItemID = nil
            return
        }

        guard let newDiscount = Double(editedItemDiscountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              newDiscount >= 0 else {
            checkoutError = "Enter a valid item discount."
            return
        }

        cart[index].discountAmount = min(newDiscount, cart[index].subtotal)
        self.editingDiscountItemID = nil
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
                    .pickerStyle(.inline)
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
}
