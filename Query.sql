with stock_quant_cte as (
    select
        stock_quant.product_id,
        sum(stock_quant.quantity) as quantity
    from stock_quant
    left join stock_location on stock_location.id = stock_quant.location_id
    where stock_location.usage = 'internal'
    group by stock_quant.product_id
),
avarage_sale_cte as (
    select
        sale_order_line.product_uom_qty,
        sale_order_line.product_id
    from sale_order_line
    left join sale_order on sale_order_line.order_id = sale_order.id
    where sale_order.date_order > (CURRENT_DATE - INTERVAL '100 DAY')::DATE
),
merch_outdated_cte as (
    select
        product_product.id,
        layer_outdated.quantity + coalesce(sum(case when stock_valuation_layer.quantity < 0 then stock_valuation_layer.quantity else 0 end), 0) as qty_old
    from stock_valuation_layer
    left join product_product on product_product.id = stock_valuation_layer.product_id
    left join (
        select 
            sum(stock_valuation_layer.quantity) as quantity,
            product_product.id
        from stock_valuation_layer
        left join product_product on product_product.id = stock_valuation_layer.product_id
        where stock_valuation_layer.create_date < (CURRENT_DATE - INTERVAL '100 DAY')::DATE
            and stock_valuation_layer.quantity > 0
        group by product_product.id
    ) as layer_outdated on layer_outdated.id = product_product.id
    group by product_product.id, layer_outdated.quantity
),
sale_quant_cte as (
    select
        sum(sale_order_line.product_uom_qty) as product_uom_qty,
        sale_order_line.product_id
    from sale_order_line
    left join sale_order on sale_order_line.order_id = sale_order.id
    where sale_order.date_order > (CURRENT_DATE - INTERVAL '30 DAY')::DATE
    group by sale_order_line.product_id
),
sale_quant_14d_cte as (
    select
        sum(sale_order_line.product_uom_qty) as product_uom_qty,
        sale_order_line.product_id
    from sale_order_line
    left join sale_order on sale_order_line.order_id = sale_order.id
    where sale_order.date_order > (CURRENT_DATE - INTERVAL '14 DAY')::DATE
    group by sale_order_line.product_id
),
sale_quant_6m_cte as (
    select
        sum(sale_order_line.product_uom_qty) as product_uom_qty,
        sale_order_line.product_id
    from sale_order_line
    left join sale_order on sale_order_line.order_id = sale_order.id
    where sale_order.date_order > (CURRENT_DATE - INTERVAL '6 MONTH')::DATE
    group by sale_order_line.product_id
)
select 
    product_template.name as "Nazwa produktu",
    product_template.default_code as "Kod produktu",
    coalesce(sale_quant_14d_cte.product_uom_qty, 0) as "Sprzedaż dzienna (14 dni)",
    coalesce(sale_quant_cte.product_uom_qty, 0) as "Sprzedaż dzienna (30 dni)",
    coalesce(sale_quant_6m_cte.product_uom_qty, 0) as "Sprzedaż dzienna (6 miesięcy)",
    coalesce(stock_quant_cte.quantity, 0) as "Ilość na stanie",
    case
        when stock_quant_cte.quantity is null or sum(avarage_sale_cte.product_uom_qty) = 0 then 0
        else stock_quant_cte.quantity / (sum(avarage_sale_cte.product_uom_qty) / 30)
    end as "Zapas w dniach",
    case
        when merch_outdated_cte.qty_old > 0 then merch_outdated_cte.qty_old
        else 0
    end as "Towar zalegający (100 dni+)",
    case
        when (sum(avarage_sale_cte.product_uom_qty) - coalesce(stock_quant_cte.quantity, 0)) > 0 then (sum(avarage_sale_cte.product_uom_qty) - coalesce(stock_quant_cte.quantity, 0))
        else 0
    end as "Ilość sugerowana do zakupu"
from product_product 
left join product_template on product_template.id = product_product.product_tmpl_id
left join product_supplierinfo on product_supplierinfo.product_tmpl_id = product_template.id and product_supplierinfo.sequence = 1
left join res_partner on res_partner.id = product_supplierinfo.name
left join stock_quant_cte on stock_quant_cte.product_id = product_product.id
left join avarage_sale_cte on avarage_sale_cte.product_id = product_product.id
left join merch_outdated_cte on merch_outdated_cte.id = product_product.id
left join sale_quant_cte on product_product.id = sale_quant_cte.product_id
left join sale_quant_14d_cte on product_product.id = sale_quant_14d_cte.product_id
left join sale_quant_6m_cte on product_product.id = sale_quant_6m_cte.product_id
where product_template.active = true
group by product_template.name, product_template.default_code, stock_quant_cte.quantity, merch_outdated_cte.qty_old, sale_quant_cte.product_uom_qty, sale_quant_14d_cte.product_uom_qty, sale_quant_6m_cte.product_uom_qty, product_product.id;s