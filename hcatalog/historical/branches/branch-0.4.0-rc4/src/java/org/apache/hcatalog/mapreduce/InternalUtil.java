/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.hcatalog.mapreduce;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.hive.metastore.MetaStoreUtils;
import org.apache.hadoop.hive.metastore.api.FieldSchema;
import org.apache.hadoop.hive.metastore.api.StorageDescriptor;
import org.apache.hadoop.hive.serde2.SerDe;
import org.apache.hadoop.hive.serde2.SerDeException;
import org.apache.hadoop.hive.serde2.objectinspector.ListObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.MapObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspectorFactory;
import org.apache.hadoop.hive.serde2.objectinspector.StructObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.primitive.PrimitiveObjectInspectorFactory;
import org.apache.hadoop.hive.serde2.typeinfo.ListTypeInfo;
import org.apache.hadoop.hive.serde2.typeinfo.MapTypeInfo;
import org.apache.hadoop.hive.serde2.typeinfo.PrimitiveTypeInfo;
import org.apache.hadoop.hive.serde2.typeinfo.StructTypeInfo;
import org.apache.hadoop.hive.serde2.typeinfo.TypeInfo;
import org.apache.hadoop.hive.serde2.typeinfo.TypeInfoUtils;
import org.apache.hadoop.mapred.Reporter;
import org.apache.hadoop.mapreduce.TaskAttemptContext;
import org.apache.hcatalog.common.HCatUtil;
import org.apache.hcatalog.data.schema.HCatFieldSchema;
import org.apache.hcatalog.data.schema.HCatSchema;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;

class InternalUtil {

    static StorerInfo extractStorerInfo(StorageDescriptor sd, Map<String, String> properties) throws IOException {
        Properties hcatProperties = new Properties();
        for (String key : properties.keySet()){
            hcatProperties.put(key, properties.get(key));
        }
        
        // also populate with StorageDescriptor->SerDe.Parameters
        for (Map.Entry<String, String>param :
            sd.getSerdeInfo().getParameters().entrySet()) {
          hcatProperties.put(param.getKey(), param.getValue());
        }


        return new StorerInfo(
                sd.getInputFormat(), sd.getOutputFormat(), sd.getSerdeInfo().getSerializationLib(),
                properties.get(org.apache.hadoop.hive.metastore.api.Constants.META_TABLE_STORAGE),
                hcatProperties);
    }

  static StructObjectInspector createStructObjectInspector(HCatSchema outputSchema) throws IOException {

    if(outputSchema == null ) {
      throw new IOException("Invalid output schema specified");
    }

    List<ObjectInspector> fieldInspectors = new ArrayList<ObjectInspector>();
    List<String> fieldNames = new ArrayList<String>();

    for(HCatFieldSchema hcatFieldSchema : outputSchema.getFields()) {
      TypeInfo type = TypeInfoUtils.getTypeInfoFromTypeString(hcatFieldSchema.getTypeString());

      fieldNames.add(hcatFieldSchema.getName());
      fieldInspectors.add(getObjectInspector(type));
    }

    StructObjectInspector structInspector = ObjectInspectorFactory.
        getStandardStructObjectInspector(fieldNames, fieldInspectors);
    return structInspector;
  }

  private static ObjectInspector getObjectInspector(TypeInfo type) throws IOException {

    switch(type.getCategory()) {

    case PRIMITIVE :
      PrimitiveTypeInfo primitiveType = (PrimitiveTypeInfo) type;
      return PrimitiveObjectInspectorFactory.
        getPrimitiveJavaObjectInspector(primitiveType.getPrimitiveCategory());

    case MAP :
      MapTypeInfo mapType = (MapTypeInfo) type;
      MapObjectInspector mapInspector = ObjectInspectorFactory.getStandardMapObjectInspector(
          getObjectInspector(mapType.getMapKeyTypeInfo()), getObjectInspector(mapType.getMapValueTypeInfo()));
      return mapInspector;

    case LIST :
      ListTypeInfo listType = (ListTypeInfo) type;
      ListObjectInspector listInspector = ObjectInspectorFactory.getStandardListObjectInspector(
          getObjectInspector(listType.getListElementTypeInfo()));
      return listInspector;

    case STRUCT :
      StructTypeInfo structType = (StructTypeInfo) type;
      List<TypeInfo> fieldTypes = structType.getAllStructFieldTypeInfos();

      List<ObjectInspector> fieldInspectors = new ArrayList<ObjectInspector>();
      for(TypeInfo fieldType : fieldTypes) {
        fieldInspectors.add(getObjectInspector(fieldType));
      }

      StructObjectInspector structInspector = ObjectInspectorFactory.getStandardStructObjectInspector(
          structType.getAllStructFieldNames(), fieldInspectors);
      return structInspector;

    default :
      throw new IOException("Unknown field schema type");
    }
  }

  //TODO this has to find a better home, it's also hardcoded as default in hive would be nice
  // if the default was decided by the serde
  static void initializeOutputSerDe(SerDe serDe, Configuration conf, 
                                    OutputJobInfo jobInfo) 
  throws SerDeException {
    initializeSerDe(serDe, conf, jobInfo.getTableInfo(), 
                    jobInfo.getOutputSchema()); 
  }

  static void initializeInputSerDe(SerDe serDe, Configuration conf, 
                                   HCatTableInfo info, HCatSchema s)
  throws SerDeException {
    initializeSerDe(serDe, conf, info, s); 
  }

  static void initializeSerDe(SerDe serDe, Configuration conf, 
                              HCatTableInfo info, HCatSchema s)
  throws SerDeException {
     Properties props = new Properties();
    List<FieldSchema> fields = HCatUtil.getFieldSchemaList(s.getFields());
    props.setProperty(org.apache.hadoop.hive.serde.Constants.LIST_COLUMNS,
          MetaStoreUtils.getColumnNamesFromFieldSchema(fields));
    props.setProperty(org.apache.hadoop.hive.serde.Constants.LIST_COLUMN_TYPES,
          MetaStoreUtils.getColumnTypesFromFieldSchema(fields));

    // setting these props to match LazySimpleSerde
    props.setProperty(org.apache.hadoop.hive.serde.Constants.SERIALIZATION_NULL_FORMAT, "\\N");
    props.setProperty(org.apache.hadoop.hive.serde.Constants.SERIALIZATION_FORMAT, "1");

    //add props from params set in table schema
    props.putAll(info.getStorerInfo().getProperties());

    serDe.initialize(conf,props);
  }

static Reporter createReporter(TaskAttemptContext context) {
      return new ProgressReporter(context);
  }

}