package com.retailvault.entity.oltp;

import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "categories", schema = "dbo")
public class Category {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "category_id")
    private Integer categoryId;
    @Column(name = "category_name")
    private String categoryName;
    @Column(name = "parent_category")
    private String parentCategory;
}
