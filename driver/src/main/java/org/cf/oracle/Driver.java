package org.cf.oracle;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.io.UnsupportedEncodingException;
import java.lang.Class;
import java.lang.reflect.InvocationTargetException;
import java.lang.UnsatisfiedLinkError;
import java.lang.VerifyError;
import java.lang.ExceptionInInitializerError;
import java.lang.RuntimeException;
import java.lang.NoClassDefFoundError;
import java.lang.reflect.Method;
import java.lang.reflect.Type;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.io.BufferedWriter;
import java.io.StringWriter;
import java.io.FileWriter;

import org.cf.oracle.options.InvocationTarget;
import org.cf.oracle.options.TargetParser;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonSerializer;
import com.google.gson.JsonPrimitive;
import com.google.gson.JsonSerializationContext;
import com.google.gson.JsonElement;

public class Driver {

    private static final String DRIVER_DIR = "/data/local";
    private static final String OUTPUT_HEADER = "===ORACLE DRIVER OUTPUT===\n";
    private static final String EXCEPTION_LOG = "od-exception.txt";
    private static final String DEBUG_LOG = "od-debug.txt";
    private static final String OUTPUT_FILE = "od-output.json";
    private static Gson GSON = buildGson();
    
    private static Gson buildGson() {
        GsonBuilder gsonBuilder = new GsonBuilder();
        JsonSerializer<Class> serializer = new JsonSerializer<Class>() {
            @Override
            public JsonElement serialize(Class src, Type typeOfSrc, JsonSerializationContext context) {
                JsonPrimitive value = new JsonPrimitive(ClassNameUtils.toInternal(src));
                return value;
            }
        };
        gsonBuilder.registerTypeAdapter(Class.class, serializer);

        gsonBuilder.disableHtmlEscaping();

        return gsonBuilder.create();
    }
    private static void debug_log(String msg) {

        try (FileWriter f = new FileWriter(DEBUG_LOG, true);
                BufferedWriter b = new BufferedWriter(f);
                PrintWriter p = new PrintWriter(b);) {

            p.println(msg);

        } catch (IOException i) {
            i.printStackTrace();
        }
    }
    private static void die(String msg, Exception exception) {
        PrintWriter writer;
        try {
            writer = new PrintWriter(EXCEPTION_LOG, "UTF-8");
        } catch (Exception e) {
            return;
        }
        writer.println(msg);
        writer.println(exception);
        StringWriter sw = new StringWriter();
        exception.printStackTrace(new PrintWriter(sw));
        writer.println(sw.toString());
        writer.close();

        // app_process, dalvikvm, and dvz don't propagate exit codes, so this doesn't matter
        System.exit(-1);
    }

    private static String invokeMethod(Method method, Object[] arguments) throws IllegalAccessException,IllegalArgumentException, InvocationTargetException,ClassNotFoundException,ExceptionInInitializerError, UnsatisfiedLinkError,NoClassDefFoundError {
        method.setAccessible(true);
        Object returnObject = null;
        returnObject = method.invoke(null, arguments);
            Class<?> returnClass = method.getReturnType();
        if (returnClass.getName().equals("Ljava.lang.Void;")) {
            // I hear an ancient voice, whispering from the Void, and it chills my lightless heart...
            return null;
        }

        String output = "";
        try {
            output = GSON.toJson(returnClass.cast(returnObject));
        } catch (Exception ex) {
            output = GSON.toJson(returnObject);
        }

        return output;
    }

    private static String invokeMethodWithInstance(String klass,Method method, Object[] arguments) throws IllegalAccessException,UnsatisfiedLinkError,
    IllegalArgumentException, InvocationTargetException, InstantiationException , ClassNotFoundException{
        method.setAccessible(true);
        Class<?> klazz = null;
        klazz = Class.forName(klass);
        Object o = klazz.newInstance();
        Object returnObject = null;
        try{
            returnObject = method.invoke(o,arguments);
        }
        catch(Throwable ex){
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);

            debug_log(sw.toString());
        }
        
        Class<?> returnClass = method.getReturnType();
        if (returnClass.getName().equals("Ljava.lang.Void;")) {
            // I hear an ancient voice, whispering from the Void, and it chills my lightless heart...
            return null;
        }
        String output = "";
        try {
            output = GSON.toJson(returnClass.cast(returnObject));
        } catch (Exception ex) {
            output = GSON.toJson(returnObject);
        }
        String a = (String) arguments[0];
        debug_log(klazz.toString() + " " + returnObject.toString() + " " +  klass+ " " + method.getName() + " " +output + " " +a );

        return output;
    }


    private static void showUsage() {
        System.out.println("Usage: export CLASSPATH=/data/local/od.zip; app_process /system/bin org.cf.driver.Driver <class> <method> [<parameter type>:<parameter value json>]");
        System.out.println("       export CLASSPATH=/data/local/od.zip; app_process /system/bin org.cf.driver.Driver @<json file>");
    }

    public static void main(String[] args) {
        boolean multipleTargets = args.length < 2 && args[0].startsWith("@");
        if (args.length < 1 && !multipleTargets) {
            showUsage();
            System.exit(-1);
        }

        try {
            StackSpoofer.init();
        } catch (NumberFormatException | IOException e) {
            die("Error parsing stack spoof info", e);
        }

        List<InvocationTarget> targets = null;
        try {
            targets = TargetParser.parse(args, GSON);
        } catch (IOException e) {
            die("Exception parsing targets", e);
        }

        String output = null;
        if (!multipleTargets) {
            InvocationTarget target = targets.get(0);
            try {
                output = invokeMethod(target.getMethod(), target.getArguments());
            } catch (Exception e) {
                die("Error executing " + target, e);
            }

            if (output != null) {
                System.out.println(OUTPUT_HEADER + output);
            }
        } else {
            Map<String, String[]> idToOutput = new HashMap<String, String[]>();
            for (InvocationTarget target : targets) {
                String status;
                if (target.getParseException() != null) {
                    output = "Error parsing " + target;
                    status = "failure";
                } else {
                    if (target.getInstanceNeeded()){
                        try {
                            output = invokeMethodWithInstance(target.getClassName(),target.getMethod(), target.getArguments());
                            status = "success";
                        //} catch (IllegalAccessException | IllegalArgumentException | InvocationTargetException | NullPointerException e) {
                        } catch (Exception e) {
                            output = "Error executing " + target + "\nReason: " + e.toString();
                            status = "failure";
                        }
                    }
                    else{
                        try {
                            output = invokeMethod(target.getMethod(), target.getArguments());
                            status = "success";
                        } catch (ClassNotFoundException | IllegalAccessException | LinkageError | InvocationTargetException e) {
                            
                            output = "Error executing " + target + "\nReason: " + e.toString();
                            status = "failure";
                        }
                    }
                }
                idToOutput.put(target.getId(), new String[] { status, output });
                
            }

            String json = GSON.toJson(idToOutput);
            try {
                FileUtils.writeFile(OUTPUT_FILE, json);
            } catch (FileNotFoundException | UnsupportedEncodingException e) {
                die("Unable to write output to " + OUTPUT_FILE, e);
            }

            System.out.println(OUTPUT_HEADER + "success");
            System.exit(0);
        }
    }
}
